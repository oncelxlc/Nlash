import {
  CORE_CONTROL_VERSION,
  MAX_CORE_COMMAND_LENGTH,
  MAX_CORE_RESPONSE_LENGTH,
  MAX_CORE_PROGRESS_LENGTH
} from '../constants/CoreControlConstants';
import { CoreCommandEnvelope, CoreResponseEnvelope, ProxyDelayProgress } from '../model/CoreControlModels';

export function encodeCoreCommandEnvelope(envelope: CoreCommandEnvelope): string {
  return JSON.stringify(envelope);
}

export function decodeCoreCommandEnvelope(value: string): CoreCommandEnvelope | undefined {
  let envelope: CoreCommandEnvelope;
  try {
    envelope = JSON.parse(value) as CoreCommandEnvelope;
  } catch (error) {
    return undefined;
  }
  if (envelope.version !== CORE_CONTROL_VERSION || !isRequestId(envelope.requestId) ||
    typeof envelope.command !== 'string' || envelope.command.length === 0 ||
    envelope.command.length > MAX_CORE_COMMAND_LENGTH) {
    return undefined;
  }
  return envelope;
}

export function encodeCoreResponseEnvelope(envelope: CoreResponseEnvelope): string {
  return JSON.stringify(envelope);
}

export function decodeCoreResponseEnvelope(value: string): CoreResponseEnvelope | undefined {
  let envelope: CoreResponseEnvelope;
  try {
    envelope = JSON.parse(value) as CoreResponseEnvelope;
  } catch (error) {
    return undefined;
  }
  if (envelope.version !== CORE_CONTROL_VERSION || !isRequestId(envelope.requestId) ||
    typeof envelope.response !== 'string' || envelope.response.length === 0 ||
    envelope.response.length > MAX_CORE_RESPONSE_LENGTH) {
    return undefined;
  }
  return envelope;
}

export function encodeProxyDelayProgress(progress: ProxyDelayProgress): string {
  return JSON.stringify(progress);
}

export function decodeProxyDelayProgress(value: string): ProxyDelayProgress | undefined {
  if (typeof value !== 'string' || value.length === 0 || value.length > MAX_CORE_PROGRESS_LENGTH) {
    return undefined;
  }
  let progress: ProxyDelayProgress;
  try {
    progress = JSON.parse(value) as ProxyDelayProgress;
  } catch (error) {
    return undefined;
  }
  if (!isRequestId(progress.operationId) || !isProgressName(progress.group) ||
    !isProgressName(progress.proxy) || !Number.isFinite(progress.delay) ||
    progress.delay % 1 !== 0 || progress.delay < -1 || progress.delay > 10000 ||
    typeof progress.alive !== 'boolean' ||
    (progress.errorCode !== undefined && !isDelayErrorCode(progress.errorCode))) {
    return undefined;
  }
  return progress;
}

function isDelayErrorCode(value: string): boolean {
  return value === 'TIMEOUT' || value === 'DNS' || value === 'TLS' || value === 'PROTECT' ||
    value === 'CONNECT' || value === 'UNKNOWN';
}

function isRequestId(value: string): boolean {
  return typeof value === 'string' && value.length >= 8 && value.length <= 64;
}

function isProgressName(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= 512;
}
