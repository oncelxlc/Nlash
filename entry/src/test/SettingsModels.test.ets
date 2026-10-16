import { describe, expect, it } from '@ohos/hypium';
import { DEFAULT_APP_SETTINGS, NAVIGATION_TRANSITION_OPTIONS } from '../main/ets/constants/SettingsConstants';
import { RUNTIME_REFRESH_INTERVAL_MS } from '../main/ets/constants/RuntimeConstants';
import { resolveNavigationTransition } from '../main/ets/utils/SettingsUtils';
import { NavigationTransition } from '../main/ets/model/SettingsModels';

export default function settingsModelsTest() {
  describe('settingsModels', () => {
    it('resolvesNavigationTransitionsAndMigratesMissingSettings', 0, () => {
      expect(DEFAULT_APP_SETTINGS.navigationTransition).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('NONE')).assertEqual(NavigationTransition.FADE);
      expect(NAVIGATION_TRANSITION_OPTIONS.length).assertEqual(2);
      expect(NAVIGATION_TRANSITION_OPTIONS[0]).assertEqual(NavigationTransition.FADE);
      expect(NAVIGATION_TRANSITION_OPTIONS[1]).assertEqual(NavigationTransition.SLIDE);
      expect(resolveNavigationTransition('FADE')).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('SLIDE')).assertEqual(NavigationTransition.SLIDE);
      expect(resolveNavigationTransition('')).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('unknown')).assertEqual(NavigationTransition.FADE);
    });

    it('usesOneFixedTwoSecondRefreshInterval', 0, () => {
      expect(RUNTIME_REFRESH_INTERVAL_MS).assertEqual(2000);
    });
  });
}
