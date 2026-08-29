import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CORE_COMMAND_EVENT,
  CORE_CONTROL_VERSION,
  CORE_PROGRESS_EVENT,
  CORE_RESPONSE_EVENT,
  CoreCommandEnvelope,
  decodeCoreCommandEnvelope,
  decodeProxyDelayProgress,
  encodeProxyDelayProgress,
  encodeCoreResponseEnvelope,
  MAX_CORE_RESPONSE_LENGTH
} from '../models/CoreControlProtocol';
import { CoreEvent, CoreEventType } from '../models/CoreModels';
import { VPN_BUNDLE_NAME } from '../models/VpnModels';
import { coreClient } from './CoreClient';

const DOMAIN = 0x4E4C;
const TAG = 'NlashCoreControl';

class CoreControlServer {
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private startOperation: Promise<void> | undefined;
  private unsubscribeCore: (() => void) | undefined;

  start(): Promise<void> {
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
    commonEventManager.subscribe(subscriber,
      (error: BusinessError, data: commonEventManager.CommonEventData): void => {
        if (error) {
          hilog.error(DOMAIN, TAG, 'command receive failed code=%{public}d', error.code);
          return;
        }
        const envelope = decodeCoreCommandEnvelope(data.data ?? '');
        if (envelope === undefined) {
          hilog.warn(DOMAIN, TAG, 'ignored invalid core command');
          return;
        }
        this.handleCommand(envelope).catch((): void => {
          this.publishResponse(envelope.requestId,
            '{"ok":false,"code":"INTERNAL_ERROR","message":"command execution failed"}');
        });
      });
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

  private async handleCommand(envelope: CoreCommandEnvelope): Promise<void> {
    let response = await coreClient.executeCommand(envelope.command);
    if (response.length === 0 || response.length > MAX_CORE_RESPONSE_LENGTH) {
      response = '{"ok":false,"code":"RESPONSE_TOO_LARGE","message":"command response is too large"}';
    }
    this.publishResponse(envelope.requestId, response);
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
