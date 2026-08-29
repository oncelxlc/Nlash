import { describe, expect, it } from '@ohos/hypium';
import {
  formatProfileRelativeTime,
  isProfileUpdateDue,
  normalizeProfileUpdateInterval,
  Profile,
  profileUsageRatio,
  ProfileType
} from '../main/ets/models/ProfileModels';
import {
  parseStoredProxySelections,
  selectStoredProfile,
  StoredProxySelection
} from '../main/ets/repository/PreferenceRepository';
import {
  countryCodeFlag,
  isValidIpv4,
  parseGeoIpResponse,
  shouldApplyNetworkResult
} from '../main/ets/services/LocalNetworkService';
import {
  buildDefaultImportPath,
  inferSubscriptionName,
  parseSubscriptionMetadata
} from '../main/ets/services/SubscriptionService';
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

    it('validatesPublicIpv4AndGeoIp', 0, () => {
      expect(isValidIpv4('8.8.8.8')).assertTrue();
      expect(isValidIpv4('8.8.8.999')).assertFalse();
      expect(isValidIpv4('2001:4860:4860::8888')).assertFalse();
      const snapshot = parseGeoIpResponse(
        '{"ip":"8.8.8.8","country":"United States","country_code":"US"}', '8.8.8.8');
      expect(snapshot.publicIpv4).assertEqual('8.8.8.8');
      expect(snapshot.countryCode).assertEqual('US');
      expect(countryCodeFlag('US')).assertEqual('🇺🇸');
      expect(countryCodeFlag('')).assertEqual('🌐');
    });

    it('rejectsStaleNetworkResults', 0, () => {
      expect(shouldApplyNetworkResult(2, 2, 1)).assertTrue();
      expect(shouldApplyNetworkResult(1, 2, 1)).assertFalse();
      expect(shouldApplyNetworkResult(2, 2, 0)).assertFalse();
    });

    it('parsesSubscriptionHeadersAndNames', 0, () => {
      const metadata = parseSubscriptionMetadata(JSON.parse(
        '{"PROFILE-TITLE":"My%20Cloud",' +
        '"Subscription-Userinfo":"upload=1024; download=2048; total=8192; expire=1800000000"}') as Object);
      expect(metadata.title).assertEqual('My Cloud');
      expect(metadata.uploadBytes).assertEqual(1024);
      expect(metadata.downloadBytes).assertEqual(2048);
      expect(metadata.totalBytes).assertEqual(8192);
      expect(metadata.expireAt).assertEqual(1800000000000);
      const disposition = parseSubscriptionMetadata(JSON.parse(
        '{"content-disposition":"attachment; filename=\\"Fallback.yaml\\""}') as Object);
      expect(disposition.title).assertEqual('Fallback.yaml');
      expect(inferSubscriptionName('https://example.com/path/Named.yaml?token=secret', undefined))
        .assertEqual('Named');
      expect(inferSubscriptionName('https://sub.example.com', undefined)).assertEqual('sub.example.com');
    });

    it('calculatesAutoUpdateAndProfileUsage', 0, () => {
      const now = 2_000_000_000_000;
      const profile: Profile = {
        id: 'profile', name: 'Profile', type: ProfileType.SUBSCRIPTION,
        sourceUrl: 'https://example.com/sub', localPath: '/profile.yaml',
        createdAt: now - 20 * 60 * 1000, updatedAt: now - 20 * 60 * 1000,
        lastUpdateAt: now - 15 * 60 * 1000, uploadBytes: 100,
        downloadBytes: 300, totalBytes: 1000, autoUpdateEnabled: true,
        updateIntervalMinutes: 15
      };
      expect(isProfileUpdateDue(profile, now)).assertTrue();
      expect(isProfileUpdateDue(profile, now - 1)).assertFalse();
      expect(profileUsageRatio(profile)).assertEqual(0.4);
      expect(normalizeProfileUpdateInterval(1)).assertEqual(15);
      expect(normalizeProfileUpdateInterval(20000)).assertEqual(10080);
      expect(formatProfileRelativeTime(now - 15 * 60 * 1000, now)).assertEqual('15 分钟前');
    });

    it('usesOneAndTwoProfileColumns', 0, () => {
      expect(resolveResponsiveMetrics(639).profileCardWidth).assertEqual('100%');
      expect(resolveResponsiveMetrics(640).profileCardWidth).assertEqual('48%');
      expect(resolveResponsiveMetrics(899).profileCardWidth).assertEqual('48%');
      expect(resolveResponsiveMetrics(900).profileCardWidth).assertEqual('48%');
      expect(resolveResponsiveMetrics(640, true).profileCardWidth).assertEqual('48%');
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
