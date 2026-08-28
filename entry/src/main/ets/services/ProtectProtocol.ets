import { buffer } from '@kit.ArkTS';

export const PROTECT_PROTOCOL_VERSION: number = 1;
export const PROTECT_MAX_PAYLOAD_BYTES: number = 4096;
export const PROTECT_ACK_TIMEOUT_MS: number = 3000;

export enum ProtectMessageType {
  REQUEST = 'protectRequest',
  ACK = 'protectAck'
}

export enum ProtectProtocolErrorCode {
  INVALID_LENGTH = 'INVALID_LENGTH',
  INVALID_UTF8 = 'INVALID_UTF8',
  INVALID_JSON = 'INVALID_JSON',
  INVALID_MESSAGE = 'INVALID_MESSAGE',
  UNSUPPORTED_VERSION = 'UNSUPPORTED_VERSION'
}

export interface ProtectWireMessage {
  version: number;
  type: string;
  requestId: number;
  generation: string;
  fd?: number;
  ok?: boolean;
  errorCode?: string;
  message?: string;
}

export interface ProtectRequest extends ProtectWireMessage {
  type: ProtectMessageType.REQUEST;
  fd: number;
}

export interface ProtectAck extends ProtectWireMessage {
  type: ProtectMessageType.ACK;
  ok: boolean;
}

export class ProtectProtocolError extends Error {
  readonly code: ProtectProtocolErrorCode;

  constructor(code: ProtectProtocolErrorCode, message: string) {
    super(message);
    this.name = 'ProtectProtocolError';
    this.code = code;
  }
}

function isIntegerInRange(value: number, minimum: number, maximum: number): boolean {
  return Number.isFinite(value) && value % 1 === 0 && value >= minimum && value <= maximum;
}

function validateCommon(message: ProtectWireMessage): void {
  if (message.version !== PROTECT_PROTOCOL_VERSION) {
    throw new ProtectProtocolError(ProtectProtocolErrorCode.UNSUPPORTED_VERSION,
      `Unsupported protect protocol version ${message.version}`);
  }
  if (!isIntegerInRange(message.requestId, 0, 0x7FFFFFFF)) {
    throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_MESSAGE, 'Invalid requestId');
  }
  if (typeof message.generation !== 'string' || message.generation.length === 0 ||
    message.generation.length > 128) {
    throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_MESSAGE, 'Invalid generation');
  }
}

export function validateProtectMessage(message: ProtectWireMessage): void {
  validateCommon(message);
  if (message.type === ProtectMessageType.REQUEST) {
    if (message.fd === undefined || !isIntegerInRange(message.fd, 0, 0x7FFFFFFF)) {
      throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_MESSAGE, 'Invalid socket fd');
    }
    return;
  }
  if (message.type === ProtectMessageType.ACK) {
    if (typeof message.ok !== 'boolean') {
      throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_MESSAGE, 'Invalid ACK status');
    }
    if (message.errorCode !== undefined && message.errorCode.length > 64) {
      throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_MESSAGE, 'Protect error code is too long');
    }
    if (message.message !== undefined && message.message.length > 256) {
      throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_MESSAGE, 'Protect error message is too long');
    }
    return;
  }
  throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_MESSAGE,
    `Unsupported protect message type ${message.type}`);
}

export function encodeProtectMessage(message: ProtectWireMessage): ArrayBuffer {
  validateProtectMessage(message);
  const payload = buffer.from(JSON.stringify(message), 'utf8');
  if (payload.length === 0 || payload.length > PROTECT_MAX_PAYLOAD_BYTES) {
    throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_LENGTH,
      `Protect payload length ${payload.length} is invalid`);
  }

  const frame = new Uint8Array(4 + payload.length);
  const length: number = payload.length;
  frame[0] = (length >>> 24) & 0xFF;
  frame[1] = (length >>> 16) & 0xFF;
  frame[2] = (length >>> 8) & 0xFF;
  frame[3] = length & 0xFF;
  try {
    for (let index = 0; index < payload.length; index++) {
      frame[4 + index] = payload.readUInt8(index);
    }
  } catch (error) {
    throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_UTF8, 'Unable to encode protect payload');
  }
  return frame.buffer as ArrayBuffer;
}

export function createProtectAck(request: ProtectRequest, ok: boolean,
  errorCode?: string, message?: string): ProtectAck {
  return {
    version: PROTECT_PROTOCOL_VERSION,
    type: ProtectMessageType.ACK,
    requestId: request.requestId,
    generation: request.generation,
    ok: ok,
    errorCode: errorCode,
    message: message
  };
}

export class ProtectFrameDecoder {
  private pending: Uint8Array = new Uint8Array(0);

  append(chunk: ArrayBuffer): ProtectWireMessage[] {
    const input = new Uint8Array(chunk);
    if (input.byteLength > 0) {
      const combined = new Uint8Array(this.pending.byteLength + input.byteLength);
      combined.set(this.pending, 0);
      combined.set(input, this.pending.byteLength);
      this.pending = combined;
    }

    const messages: ProtectWireMessage[] = [];
    let offset = 0;
    while (this.pending.byteLength - offset >= 4) {
      const payloadLength = ((this.pending[offset] << 24) >>> 0) |
        (this.pending[offset + 1] << 16) |
        (this.pending[offset + 2] << 8) |
        this.pending[offset + 3];
      if (payloadLength === 0 || payloadLength > PROTECT_MAX_PAYLOAD_BYTES) {
        this.reset();
        throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_LENGTH,
          `Protect payload length ${payloadLength} is invalid`);
      }
      const frameLength = 4 + payloadLength;
      if (this.pending.byteLength - offset < frameLength) {
        break;
      }

      const payload = this.pending.slice(offset + 4, offset + frameLength);
      messages.push(this.decodePayload(payload));
      offset += frameLength;
    }

    if (offset > 0) {
      this.pending = this.pending.slice(offset);
    }
    return messages;
  }

  reset(): void {
    this.pending = new Uint8Array(0);
  }

  private decodePayload(payload: Uint8Array): ProtectWireMessage {
    let text: string;
    try {
      text = buffer.from(payload).toString('utf8');
      const encoded = buffer.from(text, 'utf8');
      if (encoded.length !== payload.byteLength) {
        throw new Error('UTF-8 round trip length mismatch');
      }
      for (let index = 0; index < encoded.length; index++) {
        if (encoded.readUInt8(index) !== payload[index]) {
          throw new Error('UTF-8 round trip content mismatch');
        }
      }
    } catch (error) {
      throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_UTF8, 'Protect payload is not valid UTF-8');
    }

    let message: ProtectWireMessage;
    try {
      message = JSON.parse(text) as ProtectWireMessage;
    } catch (error) {
      throw new ProtectProtocolError(ProtectProtocolErrorCode.INVALID_JSON, 'Protect payload is not valid JSON');
    }
    validateProtectMessage(message);
    return message;
  }
}
