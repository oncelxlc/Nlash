import { common, Want } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { vpnExtension } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CoreServiceState,
  ProxyState,
  RuntimeLifecycleListener,
  RuntimeLifecycleSnapshot,
  VpnState,
  VpnStateEvent,
  VpnStateListener
} from '../model/VpnModels';
import {
  decodeVpnStateEnvelope,
  resolveProxyConnectedAt,
  VpnStateSequenceTracker,
  vpnStateFromProxyState
} from '../utils/VpnUtils';
import { VPN_BUNDLE_NAME, VPN_STATE_COMMON_EVENT, VPN_STATE_EVENT } from '../constants/VpnConstants';
import { feedbackService } from './FeedbackService';
import { runtimeControlService } from './RuntimeControlService';

const DOMAIN = 0x4E4C;
const TAG = 'NlashVpnService';
const VPN_WANT: Want = {
  bundleName: VPN_BUNDLE_NAME,
  abilityName: 'ProxyVpnAbility'
};

interface ReloadCorePayload {
  profileId: string;
  configPath: string;
  profileSignature: string;
}

interface SetProxyEnabledPayload {
  enabled: boolean;
}

class VpnService {
  private applicationContext: common.ApplicationContext | undefined;
  private coreState: CoreServiceState = CoreServiceState.STOPPED;
  private proxyState: ProxyState = ProxyState.DISABLED;
  private profileId: string = '';
  private profileSignature: string = '';
  private lastMessage: string = '';
  private connectedAt: number = 0;
  private listeners: Set<VpnStateListener> = new Set<VpnStateListener>();
  private lifecycleListeners: Set<RuntimeLifecycleListener> = new Set<RuntimeLifecycleListener>();
  private startOperation: Promise<void> | undefined;
  private stopOperation: Promise<void> | undefined;
  private restartOperation: Promise<void> | undefined;
  private profileOperation: Promise<void> | undefined;
  private hostStarted: boolean = false;
  private requestedProfileSignature: string = '';
  private commonEventSubscriber: commonEventManager.CommonEventSubscriber | undefined;
  private stateChannelReady: Promise<void> = Promise.resolve();
  private stateSequenceTracker: VpnStateSequenceTracker = new VpnStateSequenceTracker();

  private readonly stateEventHandler = (event: VpnStateEvent): void => {
    this.updateLifecycle(event.coreState, event.proxyState, event.message,
      event.profileId, event.profileSignature);
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

  applyProfile(profileId: string, configPath: string, profileSignature: string): Promise<void> {
    if (this.requestedProfileSignature === profileSignature && this.hostStarted) {
      return this.profileOperation ?? Promise.resolve();
    }
    if (this.profileOperation !== undefined) {
      return this.profileOperation.then(() => this.applyProfile(profileId, configPath, profileSignature));
    }
    const operation = this.applyProfileInternal(profileId, configPath, profileSignature);
    this.profileOperation = operation;
    operation.then((): void => {
      if (this.profileOperation === operation) {
        this.profileOperation = undefined;
      }
    }, (): void => {
      if (this.profileOperation === operation) {
        this.profileOperation = undefined;
      }
    });
    return operation;
  }

  ensureHost(): Promise<void> {
    return this.applyProfile('', '', 'waiting-config');
  }

  start(): Promise<void> {
    if (this.proxyState === ProxyState.ENABLED || this.proxyState === ProxyState.ENABLING) {
      return this.startOperation ?? Promise.resolve();
    }
    if (this.stopOperation !== undefined) {
      return this.stopOperation.then(() => this.start());
    }
    if (this.startOperation === undefined) {
      const operation = this.setProxyEnabled(true);
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
    if (this.proxyState === ProxyState.DISABLED) {
      return this.stopOperation ?? Promise.resolve();
    }
    if (this.startOperation !== undefined) {
      return this.startOperation.then(() => this.stop(), () => this.stop());
    }
    if (this.stopOperation === undefined) {
      const operation = this.setProxyEnabled(false);
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
    const operation = this.executeLifecycleCommand('restartCore').then((): void => {});
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
    return operation;
  }

  getState(): VpnState {
    return vpnStateFromProxyState(this.proxyState);
  }

  getCoreState(): CoreServiceState {
    return this.coreState;
  }

  getProxyState(): ProxyState {
    return this.proxyState;
  }

  getLastMessage(): string {
    return this.lastMessage;
  }

  getConnectedAt(): number {
    return this.connectedAt;
  }

  getLifecycleSnapshot(): RuntimeLifecycleSnapshot {
    return {
      coreState: this.coreState,
      proxyState: this.proxyState,
      profileId: this.profileId,
      profileSignature: this.profileSignature,
      message: this.lastMessage
    };
  }

  subscribe(listener: VpnStateListener): () => void {
    this.listeners.add(listener);
    listener(this.getState(), this.lastMessage);
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  subscribeLifecycle(listener: RuntimeLifecycleListener): () => void {
    this.lifecycleListeners.add(listener);
    listener(this.getLifecycleSnapshot());
    return (): void => {
      this.lifecycleListeners.delete(listener);
    };
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
          if (envelope === undefined || !this.stateSequenceTracker.accept(envelope)) {
            return;
          }
          const event = envelope.event;
          this.hostStarted = true;
          this.updateLifecycle(event.coreState, event.proxyState, event.message,
            event.profileId, event.profileSignature);
        });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'cross-process state subscription failed');
    }
  }

  private async applyProfileInternal(profileId: string, configPath: string,
    profileSignature: string): Promise<void> {
    await this.stateChannelReady;
    if (!this.hostStarted) {
      const startWant: Want = {
        bundleName: VPN_WANT.bundleName,
        abilityName: VPN_WANT.abilityName,
        parameters: {
          profileId: profileId,
          configPath: configPath,
          profileSignature: profileSignature
        }
      };
      this.updateLifecycle(configPath.length > 0 ? CoreServiceState.STARTING : CoreServiceState.WAITING_CONFIG,
        ProxyState.DISABLED, configPath.length > 0 ? '正在启动 Core' : '等待活动配置', profileId, profileSignature);
      await vpnExtension.startVpnExtensionAbility(startWant);
      this.hostStarted = true;
      this.requestedProfileSignature = profileSignature;
      try {
        const snapshot = await this.executeLifecycleCommand('lifecycleSnapshot');
        if (snapshot !== undefined && snapshot.profileSignature !== profileSignature) {
          await this.reloadCore(profileId, configPath, profileSignature);
        }
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'initial lifecycle handshake deferred');
      }
      return;
    }
    await this.reloadCore(profileId, configPath, profileSignature);
  }

  private async reloadCore(profileId: string, configPath: string, profileSignature: string): Promise<void> {
    const payload: ReloadCorePayload = {
      profileId: profileId,
      configPath: configPath,
      profileSignature: profileSignature
    };
    await this.executeLifecycleCommand('reloadCore', payload);
    this.requestedProfileSignature = profileSignature;
  }

  private async setProxyEnabled(enabled: boolean): Promise<void> {
    if (enabled && this.coreState !== CoreServiceState.RUNNING) {
      throw new Error(this.coreState === CoreServiceState.WAITING_CONFIG ? '请先选择活动配置' : 'Core 尚未就绪');
    }
    this.updateLifecycle(this.coreState, enabled ? ProxyState.ENABLING : ProxyState.DISABLING,
      enabled ? '正在开启代理' : '正在关闭代理', this.profileId, this.profileSignature);
    const payload: SetProxyEnabledPayload = { enabled: enabled };
    try {
      await this.executeLifecycleCommand('setProxyEnabled', payload);
    } catch (error) {
      const message = this.errorMessage(error);
      try {
        await this.executeLifecycleCommand('lifecycleSnapshot');
      } catch (snapshotError) {
        this.updateLifecycle(this.coreState, ProxyState.ERROR, message, this.profileId, this.profileSignature);
      }
      throw new Error(message);
    }
  }

  private async executeLifecycleCommand(type: string,
    payload?: Object): Promise<RuntimeLifecycleSnapshot | undefined> {
    const response = await runtimeControlService.execute<RuntimeLifecycleSnapshot>(type, payload);
    if (response.data !== undefined) {
      const data = response.data;
      this.updateLifecycle(data.coreState, data.proxyState, data.message,
        data.profileId, data.profileSignature);
    }
    if (!response.ok) {
      throw new Error(response.message.length > 0 ? response.message : response.code);
    }
    return response.data;
  }

  private updateLifecycle(coreState: CoreServiceState, proxyState: ProxyState, message: string,
    profileId: string, profileSignature: string): void {
    const previousProxyState = this.proxyState;
    const previousCoreState = this.coreState;
    this.connectedAt = resolveProxyConnectedAt(previousProxyState, proxyState, this.connectedAt, Date.now());
    this.coreState = coreState;
    this.proxyState = proxyState;
    this.profileId = profileId;
    this.profileSignature = profileSignature;
    this.lastMessage = message;
    if (previousProxyState !== proxyState) {
      if (proxyState === ProxyState.ENABLED && previousProxyState === ProxyState.ENABLING) {
        feedbackService.success('代理已开启');
      } else if (proxyState === ProxyState.DISABLED && previousProxyState === ProxyState.DISABLING) {
        feedbackService.info('代理已关闭');
      } else if (proxyState === ProxyState.ERROR) {
        feedbackService.error(message.length > 0 ? message : '代理操作失败');
      }
    } else if (previousCoreState !== coreState && coreState === CoreServiceState.ERROR) {
      feedbackService.error(message.length > 0 ? message : 'Core 运行异常');
    }
    const snapshot = this.getLifecycleSnapshot();
    this.lifecycleListeners.forEach((listener: RuntimeLifecycleListener): void => listener(snapshot));
    const vpnState = vpnStateFromProxyState(proxyState);
    this.listeners.forEach((listener: VpnStateListener): void => listener(vpnState, message));
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : 'Core 控制失败';
  }
}

export const vpnService = new VpnService();
