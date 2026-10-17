import { util } from '@kit.ArkTS';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CORE_COMMAND_EVENT,
  CORE_CONTROL_VERSION,
  CORE_PROGRESS_EVENT,
  CORE_RESPONSE_EVENT
} from '../constants/CoreControlConstants';
import {
  decodeCoreResponseEnvelope,
  decodeProxyDelayProgress,
  encodeCoreCommandEnvelope
} from '../utils/CoreControlProtocol';
import { ProxyDelayProgressListener } from '../model/CoreControlModels';
import { RuntimeCommandResponse } from '../model/RuntimeModels';
import { VPN_BUNDLE_NAME } from '../constants/VpnConstants';

const COMMAND_TIMEOUT_MS = 12000;
const DOMAIN = 0x4E4C;
const TAG = 'NlashRuntimeControl';

/** 每个在途请求拥有独立的超时器，响应、发送失败或超时后必须移除。 */
interface PendingCommand {
  resolve: (response: string) => void;
  reject: (error: Error) => void;
  timeoutId: number;
}

/** UI 进程的控制通道，以 UUID 关联 CommonEvent 请求与 Extension 返回的响应。 */
class RuntimeControlService {
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private initializeOperation: Promise<void> | undefined;
  private pending: Map<string, PendingCommand> = new Map<string, PendingCommand>();
  private progressListeners: Set<ProxyDelayProgressListener> = new Set<ProxyDelayProgressListener>();
  private loggedFirstPublish: boolean = false;
  private loggedFirstResponse: boolean = false;

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

  /** 先建立响应订阅再发送命令；这里只校验响应信封，data 的领域约束由调用方处理。 */
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
    await commonEventManager.subscribeToEvent(subscriber,
      (data: commonEventManager.CommonEventData): void => {
        const envelope = decodeCoreResponseEnvelope(data.data ?? '');
        if (envelope !== undefined) {
          if (!this.loggedFirstResponse) {
            this.loggedFirstResponse = true;
            hilog.info(DOMAIN, TAG, 'received first control response');
          }
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
    hilog.info(DOMAIN, TAG, 'response subscriber ready');
  }

  private send(requestId: string, command: string, timeoutMs: number): Promise<string> {
    return new Promise<string>((resolve: (response: string) => void, reject: (error: Error) => void): void => {
      const timeoutId = setTimeout((): void => {
        this.pending.delete(requestId);
        hilog.warn(DOMAIN, TAG, 'control request timed out request=%{public}s', requestId.substring(0, 8));
        reject(new Error('Core 控制请求超时'));
      }, timeoutMs);
      // 先登记等待项，再发布事件，避免快速响应早于 Promise 注册。
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
            if (!this.loggedFirstPublish) {
              this.loggedFirstPublish = true;
              hilog.info(DOMAIN, TAG, 'published first control request');
            }
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
