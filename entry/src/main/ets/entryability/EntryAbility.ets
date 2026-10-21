import { AbilityConstant, Configuration, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { resolveNotificationNavigationTarget } from '../utils/NotificationUtils';
import { VPN_NOTIFICATION_TARGET_PARAMETER } from '../constants/NotificationConstants';
import { Profile } from '../model/ProfileModels';
import { AppPage } from '../model/NavigationModels';
import { ProxyState, RuntimeLifecycleSnapshot } from '../model/VpnModels';
import {
  publicNetworkService,
  shouldRefreshPublicNetworkAfterProxyStateChange
} from '../services/LocalNetworkService';
import { vpnService } from '../services/VpnService';
import { navigationIntentService } from '../services/NavigationIntentService';
import { notificationPermissionService } from '../services/NotificationPermissionService';
import { vpnNotificationService } from '../services/VpnNotificationService';
import { profileStore } from '../stores/ProfileStore';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';

const DOMAIN = 0x0000;

/** UI 进程入口，装配状态服务并转发前后台事件；VPN 资源由独立 Extension 生命周期管理。 */
export default class EntryAbility extends UIAbility {
  private foreground: boolean = false;
  private proxyState: ProxyState = ProxyState.DISABLED;
  private unsubscribeVpnLifecycle: (() => void) | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleNavigationWant(want);
    vpnService.initialize(this.context.getApplicationContext());
    const hostOperation = vpnService.ensureHost();
    hostOperation.catch((): void => {
      hilog.error(DOMAIN, 'NlashCore', 'Core host initialization failed');
    });
    publicNetworkService.initialize();
    this.proxyState = vpnService.getProxyState();
    this.unsubscribeVpnLifecycle = vpnService.subscribeLifecycle((snapshot: RuntimeLifecycleSnapshot): void => {
      const previousProxyState = this.proxyState;
      this.proxyState = snapshot.proxyState;
      vpnNotificationService.updateLifecycle(snapshot.coreState, snapshot.proxyState);
      if (shouldRefreshPublicNetworkAfterProxyStateChange(previousProxyState, snapshot.proxyState)) {
        publicNetworkService.refresh();
      }
    });
    const profileOperation = profileStore.initialize(this.context);
    profileOperation.catch((): void => {
      hilog.error(DOMAIN, 'NlashProfile', 'Profile data initialization failed');
    });
    runtimeStore.initialize();
    const settingsOperation = settingsStore.initialize(this.context.getApplicationContext());
    settingsOperation.catch((): void => {
      hilog.error(DOMAIN, 'NlashSettings', 'Settings initialization failed');
    });
    // 宿主、配置和设置可并行准备，全部就绪后再恢复活动配置，避免初始化顺序竞争。
    Promise.all([hostOperation, profileOperation, settingsOperation]).then((): void => {
      const snapshot = profileStore.getSnapshot();
      const active = snapshot.profiles.find((profile: Profile): boolean =>
        profile.id === snapshot.activeProfileId);
      if (active === undefined) {
        return;
      }
      const signature = `${active.id}:${active.localPath}:${active.updatedAt}`;
      vpnService.applyProfile(active.id, active.localPath, signature).catch((): void => {
        hilog.error(DOMAIN, 'NlashCore', 'Core profile initialization failed');
      });
    }).catch((): void => {
      hilog.error(DOMAIN, 'NlashCore', 'Application runtime initialization failed');
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /** 已有窗口被通知点击重新唤起时，仍需消费新的页面跳转参数。 */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleNavigationWant(want);
  }

  onDestroy(): void {
    this.foreground = false;
    this.unsubscribeVpnLifecycle?.();
    this.unsubscribeVpnLifecycle = undefined;
    vpnNotificationService.stop().catch((): void => {
      hilog.warn(DOMAIN, 'NlashNotify', 'Notification shutdown failed');
    });
    publicNetworkService.shutdown();
    profileStore.shutdown();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
      settingsStore.onWindowReady();
    });
  }

  onConfigurationUpdate(_configuration: Configuration): void {
    settingsStore.refreshTheme();
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    this.foreground = true;
    profileStore.onForeground();
    runtimeStore.setForeground(true);
    notificationPermissionService.ensurePermission(this.context).then((enabled: boolean): Promise<void> => {
      return enabled && this.foreground ?
        vpnNotificationService.start(this.context) :
        Promise.resolve();
    }).catch((): void => {
      hilog.warn(DOMAIN, 'NlashNotify', 'Notification initialization failed');
    });
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  /** 暂停界面轮询，代理和通知继续遵循各自的服务生命周期。 */
  onBackground(): void {
    this.foreground = false;
    runtimeStore.setForeground(false);
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }

  private handleNavigationWant(want: Want): void {
    const target = resolveNotificationNavigationTarget(want.parameters?.[VPN_NOTIFICATION_TARGET_PARAMETER]);
    if (target === AppPage.DASHBOARD) {
      navigationIntentService.publish(target);
    }
  }
}
