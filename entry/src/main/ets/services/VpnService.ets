import { common, Want } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  decodeVpnStateEnvelope,
  CoreRestartAction,
  resolveCoreRestartAction,
  VPN_BUNDLE_NAME,
  VPN_STATE_COMMON_EVENT,
  VPN_STATE_EVENT,
  VpnState,
  VpnStateEvent,
  VpnStateListener,
  VpnStateSequenceTracker
} from '../models/VpnModels';
import { feedbackService } from './FeedbackService';

const DOMAIN = 0x4E4C;
const TAG = 'NlashVpnService';
const VPN_WANT: Want = {
  bundleName: 'com.zhexian.nlash',
  abilityName: 'ProxyVpnAbility'
};

class VpnService {
  private applicationContext: common.ApplicationContext | undefined;
  private state: VpnState = VpnState.IDLE;
  private lastMessage: string = '';
  private listeners: Set<VpnStateListener> = new Set<VpnStateListener>();
  private startOperation: Promise<void> | undefined;
  private stopOperation: Promise<void> | undefined;
  private restartOperation: Promise<void> | undefined;
  private commonEventSubscriber: commonEventManager.CommonEventSubscriber | undefined;
  private stateChannelReady: Promise<void> = Promise.resolve();
  private stateSequenceTracker: VpnStateSequenceTracker = new VpnStateSequenceTracker();

  private readonly stateEventHandler = (event: VpnStateEvent): void => {
    this.updateState(event.state, event.message);
  };

  initialize(applicationContext: common.ApplicationContext): void {
    if (this.applicationContext === applicationContext) {
      return;
    }
    if (this.applicationContext !== undefined) {
      this.applicationContext.eventHub.off(VPN_STATE_EVENT, this.stateEventHandler);
    }
    this.applicationContext = applicationContext;
    this.applicationContext.eventHub.on(VPN_STATE_EVENT, this.stateEventHandler);
    this.stateChannelReady = this.initializeCrossProcessStateChannel();
  }

  private async initializeCrossProcessStateChannel(): Promise<void> {
    try {
      const subscriber = await commonEventManager.createSubscriber({
        events: [VPN_STATE_COMMON_EVENT],
        publisherBundleName: VPN_BUNDLE_NAME
      });
      this.commonEventSubscriber = subscriber;
      commonEventManager.subscribe(subscriber,
        (error: BusinessError, data: commonEventManager.CommonEventData): void => {
          if (error) {
            hilog.error(DOMAIN, TAG, 'cross-process state receive failed code=%{public}d', error.code);
            return;
          }
          const envelope = decodeVpnStateEnvelope(data.data ?? '');
          if (envelope === undefined) {
            hilog.error(DOMAIN, TAG, 'ignored invalid cross-process state event');
            return;
          }
          if (!this.stateSequenceTracker.accept(envelope)) {
            hilog.warn(DOMAIN, TAG, 'ignored stale cross-process state sequence=%{public}d', envelope.sequence);
            return;
          }
          this.updateState(envelope.event.state, envelope.event.message);
        });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'cross-process state subscription failed');
    }
  }

  start(): Promise<void> {
    if (this.state === VpnState.CONNECTED || this.state === VpnState.STARTING ||
      this.state === VpnState.REQUESTING_PERMISSION) {
      hilog.info(DOMAIN, TAG, 'start ignored for state=%{public}s', this.state);
      return this.startOperation ?? Promise.resolve();
    }
    if (this.stopOperation !== undefined) {
      return this.stopOperation.then(() => this.start());
    }
    if (this.startOperation === undefined) {
      const operation = this.startInternal();
      this.startOperation = operation;
      operation.then((): void => {
        if (this.startOperation === operation) {
          this.startOperation = undefined;
        }
      }, (): void => {
        if (this.startOperation === operation) {
          this.startOperation = undefined;
        }
      });
    }
    return this.startOperation;
  }

  stop(): Promise<void> {
    if (this.state === VpnState.IDLE || this.state === VpnState.DISCONNECTED) {
      hilog.info(DOMAIN, TAG, 'stop ignored for state=%{public}s', this.state);
      return this.stopOperation ?? Promise.resolve();
    }
    if (this.startOperation !== undefined) {
      const pendingStart = this.startOperation;
      return pendingStart.then(() => this.stop(), (): void => {
        this.updateState(VpnState.DISCONNECTED, 'VPN start failed before stop');
      });
    }
    if (this.stopOperation === undefined) {
      const operation = this.stopInternal();
      this.stopOperation = operation;
      operation.then((): void => {
        if (this.stopOperation === operation) {
          this.stopOperation = undefined;
        }
      }, (): void => {
        if (this.stopOperation === operation) {
          this.stopOperation = undefined;
        }
      });
    }
    return this.stopOperation;
  }

  restart(): Promise<void> {
    if (this.restartOperation !== undefined) {
      return this.restartOperation;
    }
    const action = resolveCoreRestartAction(this.state);
    if (action === CoreRestartAction.BLOCKED) {
      return Promise.reject(new Error('Core 正在切换，请稍候再试'));
    }
    if (this.restartOperation === undefined) {
      const operation = this.restartInternal(action);
      this.restartOperation = operation;
      operation.then((): void => {
        if (this.restartOperation === operation) {
          this.restartOperation = undefined;
        }
      }, (): void => {
        if (this.restartOperation === operation) {
          this.restartOperation = undefined;
        }
      });
    }
    return this.restartOperation;
  }

  getState(): VpnState {
    return this.state;
  }

  getLastMessage(): string {
    return this.lastMessage;
  }

  subscribe(listener: VpnStateListener): () => void {
    this.listeners.add(listener);
    listener(this.state, this.lastMessage);
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  private async startInternal(): Promise<void> {
    await this.stateChannelReady;
    this.updateState(VpnState.REQUESTING_PERMISSION, 'Waiting for VPN authorization');
    try {
      await vpnExtension.startVpnExtensionAbility(VPN_WANT);
      if (this.state === VpnState.REQUESTING_PERMISSION) {
        this.updateState(VpnState.STARTING, 'VPN extension started');
      }
    } catch (error) {
      const message = this.describeError(error as BusinessError);
      hilog.error(DOMAIN, TAG, 'start failed: %{public}s', message);
      this.updateState(VpnState.ERROR, message);
      throw new Error(message);
    }
  }

  private async stopInternal(): Promise<void> {
    this.updateState(VpnState.STOPPING, 'Stopping VPN extension');
    try {
      await vpnExtension.stopVpnExtensionAbility(VPN_WANT);
      if (this.state === VpnState.STOPPING) {
        this.updateState(VpnState.DISCONNECTED, 'VPN extension stopped');
      }
    } catch (error) {
      const message = this.describeError(error as BusinessError);
      hilog.error(DOMAIN, TAG, 'stop failed: %{public}s', message);
      this.updateState(VpnState.ERROR, message);
      throw new Error(message);
    }
  }

  private async restartInternal(action: CoreRestartAction): Promise<void> {
    if (action === CoreRestartAction.START) {
      await this.start();
      return;
    }
    if (this.stopOperation !== undefined) {
      await this.stopOperation;
    } else {
      await this.stop();
    }
    await this.start();
  }

  private updateState(state: VpnState, message: string = ''): void {
    const previousState = this.state;
    const previousMessage = this.lastMessage;
    this.state = state;
    this.lastMessage = message;
    hilog.info(DOMAIN, TAG, 'state=%{public}s message=%{public}s', state, message);
    if (state !== previousState || message !== previousMessage) {
      if (state === VpnState.CONNECTED) {
        feedbackService.success('VPN 已连接');
      } else if (state === VpnState.DISCONNECTED && this.restartOperation === undefined) {
        feedbackService.info('VPN 已断开');
      } else if (state === VpnState.ERROR) {
        feedbackService.error(message.length > 0 ? message : 'VPN 操作失败');
      }
    }
    this.listeners.forEach((listener: VpnStateListener): void => {
      listener(state, message);
    });
  }

  private describeError(error: BusinessError): string {
    const code = error.code === undefined ? 'unknown' : error.code.toString();
    return `code=${code}, message=${error.message}`;
  }
}

export const vpnService = new VpnService();
