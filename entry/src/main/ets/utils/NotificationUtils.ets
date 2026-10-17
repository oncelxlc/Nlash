import { notificationManager } from '@kit.NotificationKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { AppPage } from '../model/NavigationModels';
import { VPN_NOTIFICATION_DASHBOARD_TARGET } from '../constants/NotificationConstants';
import { VpnNotificationPresentation } from '../model/NotificationModels';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { formatSpeed } from './RuntimeUtils';
import { CoreServiceState, ProxyState } from '../model/VpnModels';

/** 无有效速率时显示占位符，避免把读取失败误报为真实零流量。 */
export function buildVpnNotificationPresentation(coreState: CoreServiceState, proxyState: ProxyState,
  dashboard?: DashboardSnapshot, speedAvailable: boolean = true): VpnNotificationPresentation {
  const active = shouldShowVpnNotification(proxyState);
  let upload = '0 B/s';
  let download = '0 B/s';
  if (active) {
    if (dashboard !== undefined && speedAvailable) {
      upload = formatSpeed(dashboard.uploadSpeed);
      download = formatSpeed(dashboard.downloadSpeed);
    } else {
      upload = '--';
      download = '--';
    }
  }
  return {
    title: 'Nlash',
    text: `↑ ${upload} · ↓ ${download}`,
    additionalText: notificationStatus(coreState, proxyState),
    showPauseAction: active
  };
}

export function shouldRequestNotificationPermission(enabled: boolean, requested: boolean): boolean {
  return !enabled && !requested;
}

export function shouldShowVpnNotification(proxyState: ProxyState): boolean {
  return proxyState === ProxyState.ENABLED;
}

/** 使用持续任务分配的通知 ID 与槽位，只更新已有系统通知，不另建重复通知。 */
export function buildVpnNotificationUpdate(task: backgroundTaskManager.ContinuousTaskNotification,
  presentation: VpnNotificationPresentation): notificationManager.NotificationRequest {
  return {
    id: task.notificationId,
    label: '',
    notificationSlotType: task.slotType,
    sound: '',
    isAlertOnce: true,
    updateOnly: true,
    tapDismissed: false,
    showDeliveryTime: false,
    content: {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_SYSTEM_LIVE_VIEW,
      systemLiveView: {
        typeCode: 8,
        title: presentation.title,
        text: presentation.text,
      }
    },
    // shortcut: API 24 requires this progress template for custom text; replace when ProgressInfo is available.
    template: {
      name: 'downloadTemplate',
      data: {
        title: presentation.title,
        fileName: presentation.text,
        progressValue: 0
      }
    }
  };
}

export function resolveNotificationNavigationTarget(value: Object | undefined): AppPage | undefined {
  return typeof value === 'string' && value === VPN_NOTIFICATION_DASHBOARD_TARGET ?
    AppPage.DASHBOARD : undefined;
}

function notificationStatus(coreState: CoreServiceState, proxyState: ProxyState): string {
  if (proxyState === ProxyState.ENABLED) {
    return '代理运行中';
  }
  if (proxyState === ProxyState.ENABLING) {
    return '正在开启代理';
  }
  if (proxyState === ProxyState.DISABLING) {
    return '正在暂停代理';
  }
  if (proxyState === ProxyState.ERROR) {
    return '代理异常';
  }
  if (coreState === CoreServiceState.WAITING_CONFIG) {
    return '等待活动配置';
  }
  if (coreState === CoreServiceState.STARTING) {
    return '正在启动 Core';
  }
  if (coreState === CoreServiceState.RELOADING) {
    return '正在重载 Core';
  }
  if (coreState === CoreServiceState.ERROR) {
    return 'Core 运行异常';
  }
  if (coreState === CoreServiceState.RUNNING) {
    return '代理未运行';
  }
  return '服务未启动';
}
