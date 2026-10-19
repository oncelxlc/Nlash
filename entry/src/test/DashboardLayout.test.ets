import { describe, expect, it } from '@ohos/hypium';
import { DEFAULT_DASHBOARD_CARD_ORDER } from '../main/ets/constants/DashboardConstants';
import { DashboardCard } from '../main/ets/model/DashboardModels';
import {
  dashboardCardSpan, resolveDashboardCardOrder, dashboardMemoryUsage, formatMemoryMegabytes,
  buildSubscriptionUsageWave
} from '../main/ets/utils/DashboardUtils';

export default function dashboardLayoutTest() {
  describe('dashboardLayout', () => {
    it('usesFixedDefaultOrdersForCompactAndWideScreens', 0, () => {
      expect(resolveDashboardCardOrder(true).join(','))
        .assertEqual('publicNetwork,speed,mode,vpn,services,configuration,groups,connections,memory');
      expect(resolveDashboardCardOrder(false).join(','))
        .assertEqual('publicNetwork,speed,mode,vpn,services,configuration,memory,groups,connections');
      const copy = resolveDashboardCardOrder(true);
      copy.reverse();
      expect(resolveDashboardCardOrder(true).join(',')).assertEqual(DEFAULT_DASHBOARD_CARD_ORDER.join(','));
      expect(new Set(resolveDashboardCardOrder(false)).size).assertEqual(DEFAULT_DASHBOARD_CARD_ORDER.length);
    });

    it('givesControlCardsFullWidthAndInformationCardsResponsiveColumns', 0, () => {
      DEFAULT_DASHBOARD_CARD_ORDER.forEach((card: DashboardCard): void => {
        expect(dashboardCardSpan(card, true)).assertEqual(2);
      });
      expect(dashboardCardSpan(DashboardCard.SPEED, false)).assertEqual(2);
      expect(dashboardCardSpan(DashboardCard.PUBLIC_NETWORK, false)).assertEqual(2);
      expect(dashboardCardSpan(DashboardCard.MODE, false)).assertEqual(2);
      expect(dashboardCardSpan(DashboardCard.VPN, false)).assertEqual(2);
      expect(dashboardCardSpan(DashboardCard.CONNECTIONS, false)).assertEqual(2);
      expect(dashboardCardSpan(DashboardCard.CONFIGURATION, false)).assertEqual(1);
      expect(dashboardCardSpan(DashboardCard.MEMORY, false)).assertEqual(1);
      expect(dashboardCardSpan(DashboardCard.GROUPS, false)).assertEqual(1);
    });

    it('combinesAppAndCoreMemoryWithoutTreatingMissingSamplesAsZero', 0, () => {
      const usage = dashboardMemoryUsage(262.8 * 1048576, 13.5 * 1048576);
      expect(formatMemoryMegabytes(usage.totalBytes)).assertEqual('276.3');
      expect(formatMemoryMegabytes(usage.appBytes)).assertEqual('262.8');
      expect(formatMemoryMegabytes(usage.coreBytes)).assertEqual('13.5');
      expect(usage.appRatio > 0.95 && usage.appRatio < 0.96).assertTrue();
      expect(dashboardMemoryUsage(0, 0).totalBytes).assertEqual(0);
      expect(dashboardMemoryUsage(0, 0).appRatio).assertEqual(0);
      expect(dashboardMemoryUsage(1024, 0).appRatio).assertEqual(1);
      expect(dashboardMemoryUsage(0, 1024).appRatio).assertEqual(0);
      expect(dashboardMemoryUsage(1024, undefined).totalBytes).assertUndefined();
      expect(dashboardMemoryUsage(undefined, 1024).totalBytes).assertUndefined();
      expect(dashboardMemoryUsage(-1, 1024).appBytes).assertUndefined();
      expect(dashboardMemoryUsage(Number.NaN, 1024).appBytes).assertUndefined();
      expect(dashboardMemoryUsage(1024, Number.POSITIVE_INFINITY).coreBytes).assertUndefined();
      expect(formatMemoryMegabytes(undefined)).assertEqual('—');
    });

    it('boundsTheSubscriptionWaveToTheAvailableQuotaTrack', 0, () => {
      expect(buildSubscriptionUsageWave(100, 12, 0)).assertEqual('');
      expect(buildSubscriptionUsageWave(100, 12, Number.NaN)).assertEqual('');
      expect(buildSubscriptionUsageWave(0, 12, 0.5)).assertEqual('');
      expect(buildSubscriptionUsageWave(100, 0, 0.5)).assertEqual('');
      expect(buildSubscriptionUsageWave(100, 12, 0.48).endsWith('48 6')).assertTrue();
      expect(buildSubscriptionUsageWave(100, 12, 1.5)).assertEqual(buildSubscriptionUsageWave(100, 12, 1));
      expect(buildSubscriptionUsageWave(100, 12, 0.01).endsWith('1 6')).assertTrue();
    });
  });
}
