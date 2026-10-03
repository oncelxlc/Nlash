import { describe, expect, it } from '@ohos/hypium';
import {
  buildVpnNotificationPresentation,
  resolveNotificationNavigationTarget,
  shouldRequestNotificationPermission
} from '../main/ets/utils/NotificationUtils';
import { VPN_NOTIFICATION_DASHBOARD_TARGET } from '../main/ets/constants/NotificationConstants';
import { ActivityTab, AppPage } from '../main/ets/model/NavigationModels';
import { AppNavigationState } from '../main/ets/navigation/AppNavigationState';
import { DashboardSnapshot, RuntimeMode } from '../main/ets/model/RuntimeModels';
import { CoreServiceState, ProxyState } from '../main/ets/model/VpnModels';

export default function notificationModelsTest() {
  describe('notificationModels', () => {
    it('showsTrafficAndPauseOnlyWhileProxyIsEnabled', 0, () => {
      const dashboard: DashboardSnapshot = {
        mode: RuntimeMode.RULE,
        uploadSpeed: 1024,
        downloadSpeed: 2048,
        uploadTotal: 0,
        downloadTotal: 0,
        memoryBytes: 0,
        connectionCount: 0
      };
      const presentation = buildVpnNotificationPresentation(
        CoreServiceState.RUNNING, ProxyState.ENABLED, dashboard);

      expect(presentation.text).assertEqual('↑ 1.0 KiB/s · ↓ 2.0 KiB/s');
      expect(presentation.additionalText).assertEqual('代理运行中');
      expect(presentation.showPauseAction).assertTrue();
    });

    it('hidesPauseAndResetsTrafficForInactiveStates', 0, () => {
      const disabled = buildVpnNotificationPresentation(CoreServiceState.RUNNING, ProxyState.DISABLED);
      const enabling = buildVpnNotificationPresentation(CoreServiceState.RUNNING, ProxyState.ENABLING);
      const disabling = buildVpnNotificationPresentation(CoreServiceState.RUNNING, ProxyState.DISABLING);
      const failed = buildVpnNotificationPresentation(CoreServiceState.ERROR, ProxyState.ERROR);

      expect(disabled.text).assertEqual('↑ 0 B/s · ↓ 0 B/s');
      expect(disabled.additionalText).assertEqual('代理未运行');
      expect(disabled.showPauseAction).assertFalse();
      expect(enabling.showPauseAction).assertFalse();
      expect(disabling.additionalText).assertEqual('正在暂停代理');
      expect(disabling.showPauseAction).assertFalse();
      expect(failed.showPauseAction).assertFalse();
    });

    it('usesPlaceholderWhenAnActiveTrafficSampleFails', 0, () => {
      const presentation = buildVpnNotificationPresentation(
        CoreServiceState.RUNNING, ProxyState.ENABLED, undefined, false);

      expect(presentation.text).assertEqual('↑ -- · ↓ --');
      expect(presentation.showPauseAction).assertTrue();
    });

    it('requestsPermissionOnlyOnceWhenDisabled', 0, () => {
      expect(shouldRequestNotificationPermission(false, false)).assertTrue();
      expect(shouldRequestNotificationPermission(false, true)).assertFalse();
      expect(shouldRequestNotificationPermission(true, false)).assertFalse();
    });

    it('acceptsOnlyTheDashboardNotificationTarget', 0, () => {
      const target = resolveNotificationNavigationTarget(VPN_NOTIFICATION_DASHBOARD_TARGET);
      expect(target).assertEqual(AppPage.DASHBOARD);
      const navigationState = new AppNavigationState();
      navigationState.selectPage(AppPage.REQUESTS);
      if (target !== undefined) {
        navigationState.selectPage(target);
      }
      expect(navigationState.selectedPage).assertEqual(AppPage.DASHBOARD);
      expect(navigationState.activityTab).assertEqual(ActivityTab.REQUESTS);
      expect(resolveNotificationNavigationTarget('proxy')).assertUndefined();
      expect(resolveNotificationNavigationTarget(undefined)).assertUndefined();
    });
  });
}
