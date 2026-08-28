import { BusinessError } from '@kit.BasicServicesKit';
import { socket } from '@kit.NetworkKit';
import {
  createProtectAck,
  encodeProtectMessage,
  ProtectAck,
  ProtectFrameDecoder,
  ProtectMessageType,
  ProtectRequest,
  ProtectWireMessage
} from './ProtectProtocol';

export enum ProtectFailureCode {
  STALE_GENERATION = 'STALE_GENERATION',
  DUPLICATE_REQUEST = 'DUPLICATE_REQUEST',
  PROTECT_FAILED = 'PROTECT_FAILED',
  INVALID_MESSAGE_TYPE = 'INVALID_MESSAGE_TYPE'
}

export interface SocketProtector {
  protect(socketFd: number): Promise<void>;
}

export type ProtectChannelErrorListener = (message: string) => void;

export class ProtectRequestCoordinator {
  private readonly generation: string;
  private readonly protector: SocketProtector;
  private readonly seenRequestIds: Set<number> = new Set<number>();

  constructor(generation: string, protector: SocketProtector) {
    this.generation = generation;
    this.protector = protector;
  }

  async handle(message: ProtectWireMessage): Promise<ProtectAck> {
    if (message.type !== ProtectMessageType.REQUEST || message.fd === undefined) {
      const invalidRequest = message as ProtectRequest;
      return createProtectAck(invalidRequest, false, ProtectFailureCode.INVALID_MESSAGE_TYPE,
        'Expected protect request');
    }

    const request = message as ProtectRequest;
    if (request.generation !== this.generation) {
      return createProtectAck(request, false, ProtectFailureCode.STALE_GENERATION,
        'Protect request belongs to an inactive runtime generation');
    }
    if (this.seenRequestIds.has(request.requestId)) {
      return createProtectAck(request, false, ProtectFailureCode.DUPLICATE_REQUEST,
        'Protect requestId was already processed');
    }

    this.seenRequestIds.add(request.requestId);
    try {
      await this.protector.protect(request.fd);
      return createProtectAck(request, true);
    } catch (error) {
      return createProtectAck(request, false, ProtectFailureCode.PROTECT_FAILED,
        'VpnConnection.protect failed');
    }
  }
}

export class ProtectChannelServer {
  private readonly address: string;
  private readonly coordinator: ProtectRequestCoordinator;
  private readonly errorListener: ProtectChannelErrorListener;
  private server: socket.LocalSocketServer | undefined;
  private readonly clients: Map<number, socket.LocalSocketConnection> = new Map<number, socket.LocalSocketConnection>();
  private readonly decoders: Map<number, ProtectFrameDecoder> = new Map<number, ProtectFrameDecoder>();
  private readonly operations: Map<number, Promise<void>> = new Map<number, Promise<void>>();

  private readonly connectHandler = (connection: socket.LocalSocketConnection): void => {
    this.clients.set(connection.clientId, connection);
    this.decoders.set(connection.clientId, new ProtectFrameDecoder());
    connection.on('message', (info: socket.LocalSocketMessageInfo): void => {
      this.enqueueMessage(connection, info.message);
    });
    connection.on('close', (): void => {
      this.removeClient(connection.clientId);
    });
    connection.on('error', (error: BusinessError): void => {
      this.errorListener(`Protect client error code=${error.code ?? 'unknown'}`);
      this.removeClient(connection.clientId);
    });
  };

  private readonly serverErrorHandler = (error: BusinessError): void => {
    this.errorListener(`Protect server error code=${error.code ?? 'unknown'}`);
  };

  constructor(address: string, generation: string, protector: SocketProtector,
    errorListener: ProtectChannelErrorListener) {
    this.address = address;
    this.coordinator = new ProtectRequestCoordinator(generation, protector);
    this.errorListener = errorListener;
  }

  async start(): Promise<void> {
    if (this.server !== undefined) {
      return;
    }
    const server = socket.constructLocalSocketServerInstance();
    server.on('connect', this.connectHandler);
    server.on('error', this.serverErrorHandler);
    try {
      await server.listen({ address: this.address });
      this.server = server;
    } catch (error) {
      server.off('connect', this.connectHandler);
      server.off('error', this.serverErrorHandler);
      await server.close().catch((): void => {});
      const businessError = error as BusinessError;
      throw new Error(`Protect server listen failed code=${businessError.code ?? 'unknown'}`);
    }
  }

  async stop(): Promise<void> {
    const clients = Array.from(this.clients.values());
    this.clients.clear();
    this.decoders.clear();
    this.operations.clear();
    for (const client of clients) {
      client.off('message');
      client.off('close');
      client.off('error');
      try {
        await client.close();
      } catch (error) {
      }
    }

    const server = this.server;
    this.server = undefined;
    if (server !== undefined) {
      server.off('connect', this.connectHandler);
      server.off('error', this.serverErrorHandler);
      try {
        await server.close();
      } catch (error) {
      }
    }
  }

  private enqueueMessage(connection: socket.LocalSocketConnection, data: ArrayBuffer): void {
    const previous = this.operations.get(connection.clientId) ?? Promise.resolve();
    const operation = previous.then(async (): Promise<void> => {
      await this.handleMessage(connection, data);
    });
    this.operations.set(connection.clientId, operation);
    operation.then((): void => {
      if (this.operations.get(connection.clientId) === operation) {
        this.operations.delete(connection.clientId);
      }
    }, (error: Error): void => {
      if (this.operations.get(connection.clientId) === operation) {
        this.operations.delete(connection.clientId);
      }
      this.errorListener(`Protect message rejected: ${error.message}`);
      connection.close().catch((): void => {});
    });
  }

  private async handleMessage(connection: socket.LocalSocketConnection, data: ArrayBuffer): Promise<void> {
    const decoder = this.decoders.get(connection.clientId);
    if (decoder === undefined) {
      throw new Error('Protect decoder is unavailable');
    }
    const messages = decoder.append(data);
    for (const message of messages) {
      const ack = await this.coordinator.handle(message);
      try {
        await connection.send({ data: encodeProtectMessage(ack) });
      } catch (error) {
        const businessError = error as BusinessError;
        throw new Error(`Protect ACK send failed code=${businessError.code ?? 'unknown'}`);
      }
    }
  }

  private removeClient(clientId: number): void {
    this.clients.delete(clientId);
    this.decoders.delete(clientId);
    this.operations.delete(clientId);
  }
}
