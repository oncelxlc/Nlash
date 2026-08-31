import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CORE_COMMAND_EVENT,
  CORE_CONTROL_VERSION,
  CORE_PROGRESS_EVENT,
  CORE_RESPONSE_EVENT,
  MAX_CORE_RESPONSE_LENGTH
} from '../constants/CoreControlConstants';
import { CoreCommandEnvelope } from '../model/CoreControlModels';
import {
  decodeCoreCommandEnvelope,
  decodeProxyDelayProgress,
  encodeProxyDelayProgress,
  encodeCoreResponseEnvelope
} from '../utils/CoreControlProtocol';
import { CoreEvent, CoreEventType } from '../model/CoreModels';
import { VPN_BUNDLE_NAME } from '../constants/VpnConstants';
import { coreClient } from './CoreClient';

const DOMAIN = 0x4E4C;
const TAG = 'NlashCoreControl';

interface CoreCommandTypeOnly {
  type?: string;
}

export type CoreCommandInterceptor = (command: string) => Promise<string | undefined>;

class CoreControlServer {
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private startOperation: Promise<void> | undefined;
  private unsubscribeCore: (() => void) | undefined;
  private loggedFirstCommand: boolean = false;
  private loggedFirstResponse: boolean = false;
  private commandCount: number = 0;
  private interceptor: CoreCommandInterceptor | undefined;

  start(interceptor?: CoreCommandInterceptor): Promise<void> {
    this.interceptor = interceptor;
    if (this.subscriber !== undefined) {
      return Promise.resolve();
    }
    if (this.startOperation === undefined) {
      const operation = this.startInternal();
      this.startOperation = operation;
      operation.then((): void => {
        this.startOperation = undefined;
      }, (): void => {
        this.startOperation = undefined;
      });
    }
    return this.startOperation;
  }

  stop(): void {
    this.interceptor = undefined;
    this.unsubscribeCore?.();
    this.unsubscribeCore = undefined;
    const subscriber = this.subscriber;
    this.subscriber = undefined;
    if (subscriber !== undefined) {
      commonEventManager.unsubscribe(subscriber, (error: BusinessError): void => {
        if (error) {
          hilog.error(DOMAIN, TAG, 'unsubscribe failed code=%{public}d', error.code);
        }
      });
    }
  }

  private async startInternal(): Promise<void> {
    const subscriber = await commonEventManager.createSubscriber({
      events: [CORE_COMMAND_EVENT],
      publisherBundleName: VPN_BUNDLE_NAME
    });
    this.subscriber = subscriber;
    await commonEventManager.subscribeToEvent(subscriber,
      (data: commonEventManager.CommonEventData): void => {
        const envelope = decodeCoreCommandEnvelope(data.data ?? '');
        if (envelope === undefined) {
          hilog.warn(DOMAIN, TAG, 'ignored invalid core command');
          return;
        }
        if (!this.loggedFirstCommand) {
          this.loggedFirstCommand = true;
          hilog.info(DOMAIN, TAG, 'received first control command');
        }
        this.commandCount += 1;
        const commandIndex = this.commandCount;
        const commandType = this.safeCommandType(envelope.command);
        if (commandIndex <= 3) {
          hilog.info(DOMAIN, TAG, 'command begin index=%{public}d type=%{public}s', commandIndex, commandType);
        }
        this.handleCommand(envelope, commandIndex, commandType).catch((): void => {
          this.publishResponse(envelope.requestId,
            '{"ok":false,"code":"INTERNAL_ERROR","message":"command execution failed"}');
        });
      });
    hilog.info(DOMAIN, TAG, 'command subscriber ready');
    this.unsubscribeCore = coreClient.subscribe((event: CoreEvent): void => {
      if (event.type !== CoreEventType.PROXY_DELAY_PROGRESS) {
        return;
      }
      const progress = decodeProxyDelayProgress(event.message);
      if (progress !== undefined) {
        this.publishProgress(encodeProxyDelayProgress(progress));
      }
    });
  }

  private async handleCommand(envelope: CoreCommandEnvelope, commandIndex: number, commandType: string): Promise<void> {
    let response = this.interceptor === undefined ? undefined : await this.interceptor(envelope.command);
    if (response === undefined) {
      response = await coreClient.executeCommand(envelope.command);
    }
    if (commandIndex <= 3) {
      hilog.info(DOMAIN, TAG, 'command end index=%{public}d type=%{public}s', commandIndex, commandType);
    }
    if (response.length === 0 || response.length > MAX_CORE_RESPONSE_LENGTH) {
      response = '{"ok":false,"code":"RESPONSE_TOO_LARGE","message":"command response is too large"}';
    }
    this.publishResponse(envelope.requestId, response);
  }

  private safeCommandType(command: string): string {
    try {
      const parsed = JSON.parse(command) as CoreCommandTypeOnly;
      const type = parsed.type ?? '';
      return /^[A-Za-z]+$/.test(type) ? type.substring(0, 32) : 'invalid';
    } catch (error) {
      return 'invalid';
    }
  }

  private publishResponse(requestId: string, response: string): void {
    try {
      commonEventManager.publish(CORE_RESPONSE_EVENT, {
        bundleName: VPN_BUNDLE_NAME,
        data: encodeCoreResponseEnvelope({
          version: CORE_CONTROL_VERSION,
          requestId: requestId,
          response: response
        })
      }, (error: BusinessError): void => {
        if (error) {
          hilog.error(DOMAIN, TAG, 'response publish failed code=%{public}d', error.code);
        } else if (!this.loggedFirstResponse) {
          this.loggedFirstResponse = true;
          hilog.info(DOMAIN, TAG, 'published first control response');
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'response publish threw');
    }
  }

  private publishProgress(data: string): void {
    try {
      commonEventManager.publish(CORE_PROGRESS_EVENT, {
        bundleName: VPN_BUNDLE_NAME,
        data: data
      }, (error: BusinessError): void => {
        if (error) {
          hilog.error(DOMAIN, TAG, 'progress publish failed code=%{public}d', error.code);
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'progress publish threw');
    }
  }
}

export const coreControlServer = new CoreControlServer();
