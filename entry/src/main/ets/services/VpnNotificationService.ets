import { common, wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  buildVpnNotificationPresentation,
  buildVpnNotificationUpdate,
  shouldShowVpnNotification
} from '../utils/NotificationUtils';
import {
  VPN_NOTIFICATION_DASHBOARD_TARGET,
  VPN_NOTIFICATION_ID,
  VPN_NOTIFICATION_LABEL,
  VPN_NOTIFICATION_REFRESH_EVENT
} from '../constants/NotificationConstants';
import { VPN_BUNDLE_NAME } from '../constants/VpnConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { CoreServiceState, ProxyState } from '../model/VpnModels';
import { RUNTIME_REFRESH_INTERVAL_MS } from '../constants/RuntimeConstants';
import { runtimeControlService } from './RuntimeControlService';
import { feedbackService } from './FeedbackService';

const DOMAIN = 0x4E4C;
const TAG = 'NlashVpnNotification';
const ENTRY_ABILITY_NAME = 'EntryAbility';
const TAP_REQUEST_CODE = 1001;

class VpnNotificationService {
  private running: boolean = false;
  private coreState: CoreServiceState = CoreServiceState.STOPPED;
  private proxyState: ProxyState = ProxyState.DISABLED;
  private dashboard: DashboardSnapshot | undefined;
  private speedAvailable: boolean = true;
  private startOperation: Promise<void> | undefined;
  private publishQueue: Promise<void> = Promise.resolve();
  private pollTimer: number | undefined;
  private pollGeneration: number = 0;
  private subscriber: commonEventManager.CommonEventSubscriber | undefined;
  private tapWantAgent: WantAgent | undefined;
  private context: common.UIAbilityContext | undefined;
  private continuousTask: backgroundTaskManager.ContinuousTaskNotification | undefined;
  private persistentTaskBlocked: boolean = false;
  private readonly taskCancelHandler = (info: backgroundTaskManager.ContinuousTaskCancelInfo): void => {
    if (this.continuousTask?.continuousTaskId !== info.id) {
      return;
    }
    this.continuousTask = undefined;
    this.persistentTaskBlocked = true;
    this.stopPolling();
    hilog.warn(DOMAIN, TAG, 'notification task canceled reason=%{public}d', info.reason);
  };

  start(context: common.UIAbilityContext): Promise<void> {
    this.running = true;
    this.context = context;
    this.persistentTaskBlocked = false;
    if (this.startOperation === undefined && this.subscriber === undefined) {
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
    } else if (this.startOperation === undefined) {
      this.enqueuePublish();
      this.startPolling();
    }
    return this.startOperation ?? Promise.resolve();
  }

  updateLifecycle(coreState: CoreServiceState, proxyState: ProxyState): void {
    const wasActive = this.isActive();
    this.coreState = coreState;
    this.proxyState = proxyState;
    const active = this.isActive();
    if (active && !wasActive) {
      this.persistentTaskBlocked = false;
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
      await this.stopPersistentTask();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'notification task shutdown failed: %{public}s', this.errorMessage(error));
    }
    this.continuousTask = undefined;
    try {
      backgroundTaskManager.off('continuousTaskCancel', this.taskCancelHandler);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'notification task listener cleanup failed: %{public}s', this.errorMessage(error));
    }
    this.context = undefined;
    try {
      await notificationManager.cancel(VPN_NOTIFICATION_ID, VPN_NOTIFICATION_LABEL);
    } catch (error) {
    }
    const tapAgent = this.tapWantAgent;
    this.tapWantAgent = undefined;
    if (tapAgent !== undefined) {
      try {
        await wantAgent.cancel(tapAgent);
      } catch (error) {
      }
    }
  }

  private async startInternal(): Promise<void> {
    try {
      backgroundTaskManager.on('continuousTaskCancel', this.taskCancelHandler);
      this.tapWantAgent = await this.createTapWantAgent();
      try {
        await notificationManager.cancel(VPN_NOTIFICATION_ID, VPN_NOTIFICATION_LABEL);
      } catch (error) {
        if ((error as BusinessError).code !== 1600007) {
          hilog.warn(DOMAIN, TAG, 'status notification cleanup failed: %{public}s', this.errorMessage(error));
        }
      }
      const subscriber = await commonEventManager.createSubscriber({
        events: [VPN_NOTIFICATION_REFRESH_EVENT],
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
    this.startPolling();
  }

  private async createTapWantAgent(): Promise<WantAgent> {
    const target: Want = {
      bundleName: VPN_BUNDLE_NAME,
      moduleName: 'entry',
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

  private handleCommonEvent(data: commonEventManager.CommonEventData): void {
    if (this.running && data.event === VPN_NOTIFICATION_REFRESH_EVENT) {
      this.enqueuePublish();
    }
  }

  private startPolling(): void {
    this.stopPolling();
    this.refreshAndSchedule(this.pollGeneration);
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
      const response = await runtimeControlService.execute<DashboardSnapshot>('dashboardSnapshot');
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
    this.pollTimer = setTimeout((): void => {
      this.pollTimer = undefined;
      this.refreshAndSchedule(generation);
    }, RUNTIME_REFRESH_INTERVAL_MS);
  }

  private isPollingCurrent(generation: number): boolean {
    return this.running && this.isActive() && !this.persistentTaskBlocked && generation === this.pollGeneration;
  }

  private isActive(): boolean {
    return shouldShowVpnNotification(this.proxyState);
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
    if (!this.running || tapAgent === undefined) {
      return;
    }
    if (!this.isActive()) {
      try {
        await this.stopPersistentTask();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'notification task stop failed: %{public}s', this.errorMessage(error));
      }
      return;
    }
    if (this.continuousTask === undefined && !this.persistentTaskBlocked &&
      this.context !== undefined) {
      try {
        const taskRequest = new backgroundTaskManager.ContinuousTaskRequest();
        // shortcut: the system may cancel idle data-transfer tasks; revisit when a VPN notification API is available.
        taskRequest.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_DATA_TRANSFER];
        taskRequest.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_LIVE_VIEW_NOTIFICATION];
        taskRequest.wantAgent = tapAgent;
        this.continuousTask = await backgroundTaskManager.startBackgroundRunning(this.context, taskRequest);
        hilog.info(DOMAIN, TAG, 'notification task started id=%{public}d', this.continuousTask.notificationId);
      } catch (error) {
        this.persistentTaskBlocked = true;
        this.stopPolling();
        hilog.warn(DOMAIN, TAG, 'persistent notification failed: %{public}s', this.errorMessage(error));
        feedbackService.warning('常驻通知创建失败，请重新打开应用重试');
      }
    }
    const task = this.continuousTask;
    if (!this.running || !this.isActive() || task === undefined) {
      return;
    }
    const presentation = buildVpnNotificationPresentation(
      this.coreState, this.proxyState, this.dashboard, this.speedAvailable);
    const request = buildVpnNotificationUpdate(task, presentation);
    request.wantAgent = tapAgent;
    try {
      await notificationManager.publish(request);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'notification publish failed: %{public}s', this.errorMessage(error));
    }
  }

  private async stopPersistentTask(): Promise<void> {
    const task = this.continuousTask;
    const context = this.context;
    if (task === undefined || context === undefined) {
      return;
    }
    if (task.continuousTaskId === undefined) {
      await backgroundTaskManager.stopBackgroundRunning(context);
    } else {
      await backgroundTaskManager.stopBackgroundRunning(context, task.continuousTaskId);
    }
    this.continuousTask = undefined;
    hilog.info(DOMAIN, TAG, 'notification task stopped id=%{public}d', task.notificationId);
  }

  private errorMessage(error: Object): string {
    const exception = error as BusinessError;
    const message = typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : 'unknown error';
    return typeof exception.code === 'number' ? `code=${exception.code} ${message}` : message;
  }
}

export const vpnNotificationService = new VpnNotificationService();
