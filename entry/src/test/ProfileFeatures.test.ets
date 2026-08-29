import { describe, expect, it } from '@ohos/hypium';
import {
  parseStoredProxySelections,
  selectStoredProfile,
  StoredProxySelection
} from '../main/ets/repository/PreferenceRepository';
import { selectLocalIpv4, shouldApplyNetworkResult } from '../main/ets/services/LocalNetworkService';
import { buildDefaultImportPath } from '../main/ets/services/SubscriptionService';
import { resolveDashboardSpeedCardHeight, resolveResponsiveMetrics } from '../main/ets/ui/ResponsiveMetrics';

export default function profileFeaturesTest() {
  describe('profileFeatures', () => {
    it('buildsStrictDownloadImportPath', 0, () => {
      expect(buildDefaultImportPath('/storage/Users/currentUser/Download'))
        .assertEqual('/storage/Users/currentUser/Download/BygCloud.ymal');
      expect(buildDefaultImportPath('/storage/Users/currentUser/Download/'))
        .assertEqual('/storage/Users/currentUser/Download/BygCloud.ymal');
    });

    it('isolatesProxySelectionsByProfile', 0, () => {
      const records: StoredProxySelection[] = parseStoredProxySelections(
        '[{"profileId":"one","group":"Auto","proxy":"A"},' +
        '{"profileId":"two","group":"Auto","proxy":"B"}]');
      expect(selectStoredProfile(records, 'one').length).assertEqual(1);
      expect(selectStoredProfile(records, 'one')[0].proxy).assertEqual('A');
      expect(selectStoredProfile(records, 'two')[0].proxy).assertEqual('B');
    });

    it('selectsPrivateIpv4AndIgnoresTun', 0, () => {
      expect(selectLocalIpv4(['172.19.0.1', '8.8.8.8', '192.168.3.8']))
        .assertEqual('192.168.3.8');
      expect(selectLocalIpv4(['127.0.0.1'])).assertEqual('未知');
      expect(selectLocalIpv4([])).assertEqual('未知');
    });

    it('rejectsStaleNetworkResults', 0, () => {
      expect(shouldApplyNetworkResult(2, 2, 1)).assertTrue();
      expect(shouldApplyNetworkResult(1, 2, 1)).assertFalse();
      expect(shouldApplyNetworkResult(2, 2, 0)).assertFalse();
    });

    it('usesTwoAndThreeProxyColumns', 0, () => {
      expect(resolveResponsiveMetrics(639).proxyCardWidth).assertEqual('48%');
      expect(resolveResponsiveMetrics(640).proxyCardWidth).assertEqual('48%');
      expect(resolveResponsiveMetrics(899).proxyCardWidth).assertEqual('48%');
      expect(resolveResponsiveMetrics(900).proxyCardWidth).assertEqual('31%');
      expect(resolveResponsiveMetrics(640, true).proxyCardWidth).assertEqual('31%');
      const compact = resolveResponsiveMetrics(320);
      const expanded = resolveResponsiveMetrics(900);
      expect(resolveDashboardSpeedCardHeight(compact))
        .assertEqual(compact.dashboardCardHeight * 2 + compact.cardGap);
      expect(resolveDashboardSpeedCardHeight(expanded))
        .assertEqual(expanded.dashboardCardHeight * 2 + expanded.cardGap);
      expect(compact.dashboardInfoCardHeight < compact.dashboardCardHeight).assertTrue();
      expect(expanded.dashboardInfoCardHeight < expanded.dashboardCardHeight).assertTrue();
    });
  });
}
