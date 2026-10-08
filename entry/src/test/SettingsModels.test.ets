import { describe, expect, it } from '@ohos/hypium';
import { DEFAULT_APP_SETTINGS, REFRESH_INTERVAL_OPTIONS } from '../main/ets/constants/SettingsConstants';
import { isRefreshIntervalSeconds, resolveNavigationTransition, resolveRefreshIntervalMilliseconds } from '../main/ets/utils/SettingsUtils';
import { NavigationTransition } from '../main/ets/model/SettingsModels';

export default function settingsModelsTest() {
  describe('settingsModels', () => {
    it('resolvesNavigationTransitionsAndMigratesMissingSettings', 0, () => {
      expect(DEFAULT_APP_SETTINGS.navigationTransition).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('NONE')).assertEqual(NavigationTransition.NONE);
      expect(resolveNavigationTransition('FADE')).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('SLIDE')).assertEqual(NavigationTransition.SLIDE);
      expect(resolveNavigationTransition('')).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('unknown')).assertEqual(NavigationTransition.FADE);
    });

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
