export const CORE_COMMAND_EVENT = 'com.zhexian.nlash.event.CORE_COMMAND';
export const CORE_RESPONSE_EVENT = 'com.zhexian.nlash.event.CORE_RESPONSE';
export const CORE_PROGRESS_EVENT = 'com.zhexian.nlash.event.CORE_PROGRESS';
export const CORE_CONTROL_VERSION = 1;
export const MAX_CORE_COMMAND_LENGTH = 16 * 1024;
export const MAX_CORE_RESPONSE_LENGTH = 1024 * 1024;
export const MAX_CORE_PROGRESS_LENGTH = 8 * 1024;

export interface CoreCommandEnvelope {
  version: number;
  requestId: string;
  command: string;
}

export interface CoreResponseEnvelope {
  version: number;
  requestId: string;
  response: string;
}

export interface ProxyDelayProgress {
  operationId: string;
  group: string;
  proxy: string;
  delay: number;
  alive: boolean;
}

export type ProxyDelayProgressListener = (progress: ProxyDelayProgress) => void;

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
    typeof progress.alive !== 'boolean') {
    return undefined;
  }
  return progress;
}

function isRequestId(value: string): boolean {
  return typeof value === 'string' && value.length >= 8 && value.length <= 64;
}

function isProgressName(value: string): boolean {
  return typeof value === 'string' && value.length > 0 && value.length <= 512;
}
