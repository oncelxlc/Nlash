import { common, wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  buildVpnNotificationPresentation,
  VPN_NOTIFICATION_DASHBOARD_TARGET,
  VPN_NOTIFICATION_ID,
  VPN_NOTIFICATION_LABEL,
  VPN_NOTIFICATION_PAUSE_EVENT,
  VPN_NOTIFICATION_REFRESH_EVENT,
  VpnNotificationPresentation
} from '../models/NotificationModels';
import {
  DashboardSnapshot,
  RuntimeCommandResponse
} from '../models/RuntimeModels';
import { resolveRefreshIntervalMilliseconds } from '../models/SettingsModels';
import { CoreServiceState, ProxyState, VPN_BUNDLE_NAME } from '../models/VpnModels';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { coreClient } from './CoreClient';

const DOMAIN = 0x4E4C;
const TAG = 'NlashVpnNotification';
const ENTRY_ABILITY_NAME = 'EntryAbility';
const TAP_REQUEST_CODE = 1001;
const PAUSE_REQUEST_CODE = 1002;

export type NotificationPauseHandler = () => Promise<void>;

class VpnNotificationService {
  private running: boolean = false;
  private coreState: CoreServiceState = CoreServiceState.STOPPED;
  private proxyState: ProxyState = ProxyState.DISABLED;
  private dashboard: DashboardSnapshot | undefined;
  private speedAvailable: boolean = true;
  private startOperation: Promise<void> | undefined;
  private publishQueue: Promise<void> = Promise.resolve();
  private pauseOperation: Promise<void> | undefined;
  private pollTimer: number | undefined;
  private pollGeneration: number = 0;
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private tapWantAgent: WantAgent | undefined;
  private pauseWantAgent: WantAgent | undefined;
  private pauseHandler: NotificationPauseHandler | undefined;

  start(context: common.Context, pauseHandler: NotificationPauseHandler): Promise<void> {
    this.running = true;
    this.pauseHandler = pauseHandler;
    if (this.startOperation === undefined && this.subscriber === undefined) {
      const operation = this.startInternal(context);
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
    return this.startOperation ?? Promise.resolve();
  }

  updateLifecycle(coreState: CoreServiceState, proxyState: ProxyState): void {
    const wasActive = this.isActive();
    this.coreState = coreState;
    this.proxyState = proxyState;
    const active = this.isActive();
    if (active && !wasActive) {
      this.dashboard = undefined;
      this.speedAvailable = false;
      this.startPolling();
    } else if (!active && wasActive) {
      this.stopPolling();
      this.dashboard = undefined;
      this.speedAvailable = true;
    }
    this.enqueuePublish();
  }

  async stop(): Promise<void> {
    this.running = false;
    this.pauseHandler = undefined;
    this.stopPolling();
    const startOperation = this.startOperation;
    if (startOperation !== undefined) {
      try {
        await startOperation;
      } catch (error) {
      }
    }
    const subscriber = this.subscriber;
    this.subscriber = undefined;
    if (subscriber !== undefined) {
      commonEventManager.unsubscribe(subscriber, (error: BusinessError): void => {
        if (error) {
          hilog.warn(DOMAIN, TAG, 'notification event unsubscribe failed code=%{public}d', error.code);
        }
      });
    }
    try {
      await this.publishQueue;
    } catch (error) {
    }
    try {
      await notificationManager.cancel(VPN_NOTIFICATION_ID, VPN_NOTIFICATION_LABEL);
    } catch (error) {
    }
    const tapAgent = this.tapWantAgent;
    const pauseAgent = this.pauseWantAgent;
    this.tapWantAgent = undefined;
    this.pauseWantAgent = undefined;
    if (tapAgent !== undefined) {
      try {
        await wantAgent.cancel(tapAgent);
      } catch (error) {
      }
    }
    if (pauseAgent !== undefined) {
      try {
        await wantAgent.cancel(pauseAgent);
      } catch (error) {
      }
    }
  }

  private async startInternal(context: common.Context): Promise<void> {
    try {
      await preferenceRepository.initialize(context);
      this.tapWantAgent = await this.createTapWantAgent();
      this.pauseWantAgent = await this.createPauseWantAgent();
      const subscriber = await commonEventManager.createSubscriber({
        events: [VPN_NOTIFICATION_PAUSE_EVENT, VPN_NOTIFICATION_REFRESH_EVENT],
        publisherBundleName: VPN_BUNDLE_NAME
      });
      this.subscriber = subscriber;
      await commonEventManager.subscribeToEvent(subscriber,
        (data: commonEventManager.CommonEventData): void => this.handleCommonEvent(data));
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'notification service initialization failed: %{public}s',
        this.errorMessage(error));
      throw new Error(this.errorMessage(error));
    }
    if (!this.running) {
      return;
    }
    this.enqueuePublish();
    if (this.isActive()) {
      this.startPolling();
    }
  }

  private async createTapWantAgent(): Promise<WantAgent> {
    const target: Want = {
      bundleName: VPN_BUNDLE_NAME,
      abilityName: ENTRY_ABILITY_NAME,
      parameters: {
        targetPage: VPN_NOTIFICATION_DASHBOARD_TARGET
      }
    };
    try {
      return await wantAgent.getWantAgent({
        wants: [target],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: TAP_REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
    } catch (error) {
      throw new Error(this.errorMessage(error));
    }
  }

  private async createPauseWantAgent(): Promise<WantAgent> {
    const target: Want = {
      bundleName: VPN_BUNDLE_NAME,
      action: VPN_NOTIFICATION_PAUSE_EVENT
    };
    try {
      return await wantAgent.getWantAgent({
        wants: [target],
        actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
        requestCode: PAUSE_REQUEST_CODE,
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      });
    } catch (error) {
      throw new Error(this.errorMessage(error));
    }
  }

  private handleCommonEvent(data: commonEventManager.CommonEventData): void {
    if (!this.running) {
      return;
    }
    if (data.event === VPN_NOTIFICATION_REFRESH_EVENT) {
      this.enqueuePublish();
      return;
    }
    if (data.event !== VPN_NOTIFICATION_PAUSE_EVENT || !this.isActive() ||
      this.pauseHandler === undefined || this.pauseOperation !== undefined) {
      return;
    }
    const operation = this.pauseHandler();
    this.pauseOperation = operation;
    operation.then((): void => {
      if (this.pauseOperation === operation) {
        this.pauseOperation = undefined;
      }
    }, (error: Error): void => {
      if (this.pauseOperation === operation) {
        this.pauseOperation = undefined;
      }
      hilog.error(DOMAIN, TAG, 'notification pause failed: %{public}s', this.errorMessage(error));
    });
  }

  private startPolling(): void {
    this.stopPolling();
    const generation = this.pollGeneration;
    this.refreshAndSchedule(generation);
  }

  private stopPolling(): void {
    this.pollGeneration += 1;
    if (this.pollTimer !== undefined) {
      clearTimeout(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  private async refreshAndSchedule(generation: number): Promise<void> {
    if (!this.isPollingCurrent(generation)) {
      return;
    }
    try {
      const command = JSON.stringify({ type: 'dashboardSnapshot' });
      const response = JSON.parse(await coreClient.executeCommand(command)) as RuntimeCommandResponse<DashboardSnapshot>;
      if (!response.ok || response.data === undefined ||
        !Number.isFinite(response.data.uploadSpeed) || !Number.isFinite(response.data.downloadSpeed)) {
        throw new Error(response.message.length > 0 ? response.message : response.code);
      }
      if (this.isPollingCurrent(generation)) {
        this.dashboard = response.data;
        this.speedAvailable = true;
      }
    } catch (error) {
      if (this.isPollingCurrent(generation)) {
        this.dashboard = undefined;
        this.speedAvailable = false;
        hilog.warn(DOMAIN, TAG, 'traffic snapshot failed: %{public}s', this.errorMessage(error));
      }
    }
    if (!this.isPollingCurrent(generation)) {
      return;
    }
    this.enqueuePublish();
    let interval = resolveRefreshIntervalMilliseconds(0);
    try {
      const settings = await preferenceRepository.getAppSettings();
      interval = resolveRefreshIntervalMilliseconds(settings.refreshIntervalSeconds);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'notification refresh interval fallback');
    }
    if (!this.isPollingCurrent(generation)) {
      return;
    }
    this.pollTimer = setTimeout((): void => {
      this.pollTimer = undefined;
      this.refreshAndSchedule(generation);
    }, interval);
  }

  private isPollingCurrent(generation: number): boolean {
    return this.running && generation === this.pollGeneration && this.isActive();
  }

  private isActive(): boolean {
    return this.coreState === CoreServiceState.RUNNING && this.proxyState === ProxyState.ENABLED;
  }

  private enqueuePublish(): void {
    if (!this.running) {
      return;
    }
    this.publishQueue = this.publishQueue.then(
      (): Promise<void> => this.publishCurrent(),
      (): Promise<void> => this.publishCurrent());
  }

  private async publishCurrent(): Promise<void> {
    const tapAgent = this.tapWantAgent;
    const pauseAgent = this.pauseWantAgent;
    if (!this.running || tapAgent === undefined || pauseAgent === undefined) {
      return;
    }
    const presentation: VpnNotificationPresentation = buildVpnNotificationPresentation(
      this.coreState, this.proxyState, this.dashboard, this.speedAvailable);
    const request: notificationManager.NotificationRequest = {
      id: VPN_NOTIFICATION_ID,
      label: VPN_NOTIFICATION_LABEL,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      isOngoing: true,
      isUnremovable: true,
      isAlertOnce: true,
      tapDismissed: false,
      showDeliveryTime: false,
      wantAgent: tapAgent,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: presentation.title,
          text: presentation.text,
          additionalText: presentation.additionalText
        }
      }
    };
    if (presentation.showPauseAction) {
      request.actionButtons = [{
        title: '暂停',
        wantAgent: pauseAgent
      }];
    }
    try {
      await notificationManager.publish(request);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'notification publish failed: %{public}s', this.errorMessage(error));
    }
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : 'unknown error';
  }
}

export const vpnNotificationService = new VpnNotificationService();
