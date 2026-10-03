import { describe, expect, it } from '@ohos/hypium';
import { ActivityTab, AppPage } from '../main/ets/model/NavigationModels';
import { NAVIGATION_PAGES } from '../main/ets/constants/NavigationConstants';
import { AppNavigationState } from '../main/ets/navigation/AppNavigationState';
import { resolveResponsiveMetrics } from '../main/ets/utils/ResponsiveUtils';
import { configurationEditorService } from '../main/ets/services/ConfigurationEditorService';

export default function navigationModelsTest() {
  describe('navigationModels', () => {
    it('exposesExpectedNavigationItems', 0, () => {
      expect(NAVIGATION_PAGES.length).assertEqual(5);
      expect(NAVIGATION_PAGES[0]).assertEqual(AppPage.DASHBOARD);
      expect(NAVIGATION_PAGES[1]).assertEqual(AppPage.PROXY);
      expect(NAVIGATION_PAGES[2]).assertEqual(AppPage.CONFIGURATION);
      expect(NAVIGATION_PAGES[3]).assertEqual(AppPage.ACTIVITY);
      expect(NAVIGATION_PAGES[4]).assertEqual(AppPage.SETTINGS);
    });

    it('selectsPagesWithoutCreatingRoutes', 0, () => {
      const navigationState = new AppNavigationState();
      expect(navigationState.selectedPage).assertEqual(AppPage.DASHBOARD);

      navigationState.selectPage(AppPage.CONNECTIONS);
      expect(navigationState.selectedPage).assertEqual(AppPage.ACTIVITY);
      expect(navigationState.activityTab).assertEqual(ActivityTab.CONNECTIONS);

      navigationState.selectPage(AppPage.DASHBOARD);
      expect(navigationState.selectedPage).assertEqual(AppPage.DASHBOARD);
    });

    it('mapsLegacyActivityTargetsAndRemembersTheLastTab', 0, () => {
      const navigationState = new AppNavigationState();
      expect(navigationState.activityTab).assertEqual(ActivityTab.CONNECTIONS);
      navigationState.selectPage(AppPage.REQUESTS);
      expect(navigationState.selectedPage).assertEqual(AppPage.ACTIVITY);
      expect(navigationState.activityTab).assertEqual(ActivityTab.REQUESTS);
      navigationState.selectPage(AppPage.SETTINGS);
      navigationState.selectPage(AppPage.ACTIVITY);
      expect(navigationState.activityTab).assertEqual(ActivityTab.REQUESTS);
      navigationState.selectActivityTab(ActivityTab.CONNECTIONS);
      expect(navigationState.selectedPage).assertEqual(AppPage.ACTIVITY);
      expect(navigationState.activityTab).assertEqual(ActivityTab.CONNECTIONS);
      expect(NAVIGATION_PAGES.indexOf(navigationState.selectedPage)).assertEqual(3);
    });

    it('keepsEditorBackHandlingUntilTheCloseIsConfirmed', 0, () => {
      let closeRequests = 0;
      const unbind = configurationEditorService.bind((): void => { closeRequests += 1; });
      try {
        configurationEditorService.setOpen(false);
        expect(configurationEditorService.handleBack()).assertFalse();
        configurationEditorService.setOpen(true);
        expect(configurationEditorService.handleBack()).assertTrue();
        expect(closeRequests).assertEqual(1);
        // A pending unsaved-changes prompt must keep consuming the back action.
        expect(configurationEditorService.handleBack()).assertTrue();
        expect(closeRequests).assertEqual(2);
        configurationEditorService.setOpen(false);
        expect(configurationEditorService.handleBack()).assertFalse();
      } finally {
        unbind();
      }
      expect(configurationEditorService.handleBack()).assertFalse();
    });

    it('adaptsNodeColumnsAndPageGuttersAtTheExistingBreakpoints', 0, () => {
      expect(resolveResponsiveMetrics(0).proxyColumns).assertEqual('1fr');
      expect(resolveResponsiveMetrics(639).proxyColumns).assertEqual('1fr');
      expect(resolveResponsiveMetrics(640).proxyColumns).assertEqual('1fr 1fr');
      expect(resolveResponsiveMetrics(899).proxyColumns).assertEqual('1fr 1fr');
      expect(resolveResponsiveMetrics(900).proxyColumns).assertEqual('1fr 1fr 1fr');
      expect(resolveResponsiveMetrics(360, true).proxyColumns).assertEqual('1fr 1fr 1fr');
      expect(resolveResponsiveMetrics(360).pagePadding).assertEqual(16);
      expect(resolveResponsiveMetrics(700).pagePadding).assertEqual(24);
      expect(resolveResponsiveMetrics(1000).pagePadding).assertEqual(32);
    });
  });
}
