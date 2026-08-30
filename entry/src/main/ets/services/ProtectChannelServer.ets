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

export type ProtectChannelDiagnosticListener = (message: string) => void;

const DEFAULT_REQUEST_HISTORY_LIMIT = 4096;

export class ProtectRequestCoordinator {
  private readonly generation: string;
  private readonly protector: SocketProtector;
  private readonly requestHistoryLimit: number;
  private readonly seenRequestIds: Set<number> = new Set<number>();
  private readonly requestHistory: number[] = [];

  constructor(generation: string, protector: SocketProtector,
    requestHistoryLimit: number = DEFAULT_REQUEST_HISTORY_LIMIT) {
    this.generation = generation;
    this.protector = protector;
    this.requestHistoryLimit = Math.max(1, requestHistoryLimit);
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
    this.requestHistory.push(request.requestId);
    if (this.requestHistory.length > this.requestHistoryLimit) {
      const expiredRequestId = this.requestHistory.shift();
      if (expiredRequestId !== undefined) {
        this.seenRequestIds.delete(expiredRequestId);
      }
    }
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
  private readonly diagnosticListener: ProtectChannelDiagnosticListener;
  private server: socket.LocalSocketServer | undefined;
  private readonly clients: Set<socket.LocalSocketConnection> = new Set<socket.LocalSocketConnection>();
  private readonly operations: Map<socket.LocalSocketConnection, Promise<void>> =
    new Map<socket.LocalSocketConnection, Promise<void>>();

  private readonly connectHandler = (connection: socket.LocalSocketConnection): void => {
    const decoder = new ProtectFrameDecoder();
    this.clients.add(connection);
    connection.on('message', (info: socket.LocalSocketMessageInfo): void => {
      this.enqueueMessage(connection, decoder, info.message);
    });
    connection.on('close', (): void => {
      this.removeClient(connection);
    });
    connection.on('error', (error: BusinessError): void => {
      this.diagnosticListener(`Protect client error code=${error.code ?? 'unknown'}`);
      this.removeClient(connection);
    });
  };

  private readonly serverErrorHandler = (error: BusinessError): void => {
    this.diagnosticListener(`Protect server error code=${error.code ?? 'unknown'}`);
  };

  constructor(address: string, generation: string, protector: SocketProtector,
    diagnosticListener: ProtectChannelDiagnosticListener) {
    this.address = address;
    this.coordinator = new ProtectRequestCoordinator(generation, protector);
    this.diagnosticListener = diagnosticListener;
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
    const clients = Array.from(this.clients);
    this.clients.clear();
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

  private enqueueMessage(connection: socket.LocalSocketConnection, decoder: ProtectFrameDecoder,
    data: ArrayBuffer): void {
    const previous = this.operations.get(connection) ?? Promise.resolve();
    const operation = previous.then(async (): Promise<void> => {
      await this.handleMessage(connection, decoder, data);
    });
    this.operations.set(connection, operation);
    operation.then((): void => {
      if (this.operations.get(connection) === operation) {
        this.operations.delete(connection);
      }
    }, (error: Error): void => {
      if (this.operations.get(connection) === operation) {
        this.operations.delete(connection);
      }
      this.diagnosticListener(`Protect message rejected: ${error.message}`);
      connection.close().catch((): void => {});
    });
  }

  private async handleMessage(connection: socket.LocalSocketConnection, decoder: ProtectFrameDecoder,
    data: ArrayBuffer): Promise<void> {
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

  private removeClient(connection: socket.LocalSocketConnection): void {
    this.clients.delete(connection);
    this.operations.delete(connection);
  }
}
