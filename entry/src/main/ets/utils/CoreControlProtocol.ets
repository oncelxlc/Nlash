import {
  CORE_CONTROL_VERSION,
  CORE_RESPONSE_CHUNK_LENGTH,
  MAX_CORE_COMMAND_LENGTH,
  MAX_CORE_RESPONSE_LENGTH,
  MAX_CORE_RESPONSE_CHUNKS,
  MAX_CORE_PROGRESS_LENGTH
} from '../constants/CoreControlConstants';
import { CoreCommandEnvelope, CoreResponseEnvelope, ProxyDelayProgress } from '../model/CoreControlModels';

export function encodeCoreCommandEnvelope(envelope: CoreCommandEnvelope): string {
  return JSON.stringify(envelope);
}

/** 先验证跨进程信封，再由宿主或 Go 解析内层业务命令，避免两层协议耦合。 */
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

export function encodeCoreResponseChunks(envelope: CoreResponseEnvelope): string[] {
  if (envelope.response.length <= CORE_RESPONSE_CHUNK_LENGTH) {
    return [encodeCoreResponseEnvelope(envelope)];
  }
  const chunks: string[] = [];
  const count = Math.ceil(envelope.response.length / CORE_RESPONSE_CHUNK_LENGTH);
  for (let index = 0; index < count; index++) {
    chunks.push(encodeCoreResponseEnvelope({
      version: envelope.version, requestId: envelope.requestId,
      response: envelope.response.slice(index * CORE_RESPONSE_CHUNK_LENGTH, (index + 1) * CORE_RESPONSE_CHUNK_LENGTH),
      chunkIndex: index, chunkCount: count
    }));
  }
  return chunks;
}

export function decodeCoreResponseEnvelope(value: string): CoreResponseEnvelope | undefined {
  let envelope: CoreResponseEnvelope;
  try {
    envelope = JSON.parse(value) as CoreResponseEnvelope;
  } catch (error) {
    return undefined;
  }
  if (envelope === null || envelope.version !== CORE_CONTROL_VERSION || !isRequestId(envelope.requestId) ||
    typeof envelope.response !== 'string' || envelope.response.length === 0 ||
    envelope.response.length > MAX_CORE_RESPONSE_LENGTH) {
    return undefined;
  }
  if (envelope.chunkIndex !== undefined || envelope.chunkCount !== undefined) {
    const index = envelope.chunkIndex;
    const count = envelope.chunkCount;
    if (typeof index !== 'number' || typeof count !== 'number' || !Number.isInteger(index) ||
      !Number.isInteger(count) || count < 2 || count > MAX_CORE_RESPONSE_CHUNKS || index < 0 || index >= count ||
      envelope.response.length > CORE_RESPONSE_CHUNK_LENGTH) {
      return undefined;
    }
  }
  return envelope;
}

/** 公共事件可能乱序或重复，完整响应到齐后才交给业务层解析。缓冲区随请求超时一并释放。 */
export class CoreResponseBuffer {
  private chunks: Map<number, string> = new Map<number, string>();
  private count: number = 0;

  append(envelope: CoreResponseEnvelope): string | undefined {
    if (envelope.chunkIndex === undefined || envelope.chunkCount === undefined) {
      return envelope.response;
    }
    if (this.count !== 0 && this.count !== envelope.chunkCount) {
      throw new Error('Core 响应分片数量不一致');
    }
    const previous = this.chunks.get(envelope.chunkIndex);
    if (previous !== undefined && previous !== envelope.response) {
      throw new Error('Core 响应分片内容不一致');
    }
    this.count = envelope.chunkCount;
    this.chunks.set(envelope.chunkIndex, envelope.response);
    if (this.chunks.size !== this.count) { return undefined; }
    const parts: string[] = [];
    for (let index = 0; index < this.count; index++) {
      const part = this.chunks.get(index);
      if (part === undefined) { return undefined; }
      parts.push(part);
    }
    return parts.join('');
  }
}

export function encodeProxyDelayProgress(progress: ProxyDelayProgress): string {
  return JSON.stringify(progress);
}

/** 增量结果限制字段长度、延迟范围和错误分类，避免异常事件污染 UI 测速状态。 */
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
