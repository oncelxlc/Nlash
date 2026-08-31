import { AppPage } from '../model/NavigationModels';
import { VPN_NOTIFICATION_DASHBOARD_TARGET } from '../constants/NotificationConstants';
import { VpnNotificationPresentation } from '../model/NotificationModels';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { formatSpeed } from './RuntimeUtils';
import { CoreServiceState, ProxyState } from '../model/VpnModels';

export function buildVpnNotificationPresentation(coreState: CoreServiceState, proxyState: ProxyState,
  dashboard?: DashboardSnapshot, speedAvailable: boolean = true): VpnNotificationPresentation {
  const active = coreState === CoreServiceState.RUNNING && proxyState === ProxyState.ENABLED;
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
