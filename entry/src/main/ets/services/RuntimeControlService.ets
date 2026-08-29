import { util } from '@kit.ArkTS';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import {
  CORE_COMMAND_EVENT,
  CORE_CONTROL_VERSION,
  CORE_PROGRESS_EVENT,
  CORE_RESPONSE_EVENT,
  decodeCoreResponseEnvelope,
  decodeProxyDelayProgress,
  ProxyDelayProgressListener,
  encodeCoreCommandEnvelope
} from '../models/CoreControlProtocol';
import { RuntimeCommandResponse } from '../models/RuntimeModels';
import { VPN_BUNDLE_NAME } from '../models/VpnModels';

const COMMAND_TIMEOUT_MS = 12000;

interface PendingCommand {
  resolve: (response: string) => void;
  reject: (error: Error) => void;
  timeoutId: number;
}

class RuntimeControlService {
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private initializeOperation: Promise<void> | undefined;
  private pending: Map<string, PendingCommand> = new Map<string, PendingCommand>();
  private progressListeners: Set<ProxyDelayProgressListener> = new Set<ProxyDelayProgressListener>();

  initialize(): Promise<void> {
    if (this.subscriber !== undefined) {
      return Promise.resolve();
    }
    if (this.initializeOperation === undefined) {
      const operation = this.initializeInternal();
      this.initializeOperation = operation;
      operation.then((): void => {
        this.initializeOperation = undefined;
      }, (): void => {
        this.initializeOperation = undefined;
      });
    }
    return this.initializeOperation;
  }

  async execute<T>(type: string, payload?: Object,
    timeoutMs: number = COMMAND_TIMEOUT_MS): Promise<RuntimeCommandResponse<T>> {
    await this.initialize();
    const command = payload === undefined ? JSON.stringify({ type: type }) :
      JSON.stringify({ type: type, payload: payload });
    const requestId = util.generateRandomUUID();
    const response = await this.send(requestId, command, Math.max(COMMAND_TIMEOUT_MS, timeoutMs));
    let result: RuntimeCommandResponse<T>;
    try {
      result = JSON.parse(response) as RuntimeCommandResponse<T>;
    } catch (error) {
      throw new Error('Core 返回了无效响应');
    }
    if (typeof result.ok !== 'boolean' || typeof result.code !== 'string' ||
      typeof result.message !== 'string') {
      throw new Error('Core 响应字段无效');
    }
    return result;
  }

  subscribeDelayProgress(listener: ProxyDelayProgressListener): () => void {
    this.progressListeners.add(listener);
    return (): void => {
      this.progressListeners.delete(listener);
    };
  }

  private async initializeInternal(): Promise<void> {
    const subscriber = await commonEventManager.createSubscriber({
      events: [CORE_RESPONSE_EVENT, CORE_PROGRESS_EVENT],
      publisherBundleName: VPN_BUNDLE_NAME
    });
    this.subscriber = subscriber;
    commonEventManager.subscribe(subscriber,
      (error: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (error) {
          return;
        }
        const envelope = decodeCoreResponseEnvelope(data.data ?? '');
        if (envelope !== undefined) {
          const pending = this.pending.get(envelope.requestId);
          if (pending === undefined) {
            return;
          }
          clearTimeout(pending.timeoutId);
          this.pending.delete(envelope.requestId);
          pending.resolve(envelope.response);
          return;
        }
        const progress = decodeProxyDelayProgress(data.data ?? '');
        if (progress !== undefined) {
          this.progressListeners.forEach((listener: ProxyDelayProgressListener): void => listener(progress));
        }
      });
  }

  private send(requestId: string, command: string, timeoutMs: number): Promise<string> {
    return new Promise<string>((resolve: (response: string) => void, reject: (error: Error) => void): void => {
      const timeoutId = setTimeout((): void => {
        this.pending.delete(requestId);
        reject(new Error('Core 控制请求超时'));
      }, timeoutMs);
      this.pending.set(requestId, {
        resolve: resolve,
        reject: reject,
        timeoutId: timeoutId
      });
      try {
        commonEventManager.publish(CORE_COMMAND_EVENT, {
          bundleName: VPN_BUNDLE_NAME,
          data: encodeCoreCommandEnvelope({
            version: CORE_CONTROL_VERSION,
            requestId: requestId,
            command: command
          })
        }, (error: BusinessError): void => {
          if (!error) {
            return;
          }
          this.rejectPending(requestId, new Error(`Core 控制请求发送失败 code=${error.code}`));
        });
      } catch (error) {
        this.rejectPending(requestId, new Error('Core 控制请求发送失败'));
      }
    });
  }

  private rejectPending(requestId: string, error: Error): void {
    const pending = this.pending.get(requestId);
    if (pending === undefined) {
      return;
    }
    clearTimeout(pending.timeoutId);
    this.pending.delete(requestId);
    pending.reject(error);
  }
}

export const runtimeControlService = new RuntimeControlService();
