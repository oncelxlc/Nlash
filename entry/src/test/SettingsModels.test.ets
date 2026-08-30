import { describe, expect, it } from '@ohos/hypium';
import {
  DEFAULT_APP_SETTINGS,
  isRefreshIntervalSeconds,
  REFRESH_INTERVAL_OPTIONS,
  resolveRefreshIntervalMilliseconds
} from '../main/ets/models/SettingsModels';

export default function settingsModelsTest() {
  describe('settingsModels', () => {
    it('usesThreeSecondsForNewAndMigratedSettings', 0, () => {
      expect(DEFAULT_APP_SETTINGS.refreshIntervalSeconds).assertEqual(3);
      expect(REFRESH_INTERVAL_OPTIONS.length).assertEqual(4);
    });

    it('acceptsOnlySupportedRefreshIntervals', 0, () => {
      expect(isRefreshIntervalSeconds(3)).assertTrue();
      expect(isRefreshIntervalSeconds(5)).assertTrue();
      expect(isRefreshIntervalSeconds(10)).assertTrue();
      expect(isRefreshIntervalSeconds(30)).assertTrue();
      expect(isRefreshIntervalSeconds(1)).assertFalse();
      expect(isRefreshIntervalSeconds(60)).assertFalse();
      expect(resolveRefreshIntervalMilliseconds(10)).assertEqual(10000);
      expect(resolveRefreshIntervalMilliseconds(1)).assertEqual(3000);
    });
  });
}
