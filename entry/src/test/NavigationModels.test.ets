import { describe, expect, it } from '@ohos/hypium';
import { AppPage } from '../main/ets/model/NavigationModels';
import { NAVIGATION_PAGES } from '../main/ets/constants/NavigationConstants';
import { AppNavigationState } from '../main/ets/navigation/AppNavigationState';
import { resolveResponsiveMetrics } from '../main/ets/utils/ResponsiveUtils';

export default function navigationModelsTest() {
  describe('navigationModels', () => {
    it('exposesExpectedNavigationItems', 0, () => {
      expect(NAVIGATION_PAGES.length).assertEqual(6);
      expect(NAVIGATION_PAGES[0]).assertEqual(AppPage.DASHBOARD);
      expect(NAVIGATION_PAGES[1]).assertEqual(AppPage.PROXY);
      expect(NAVIGATION_PAGES[2]).assertEqual(AppPage.CONFIGURATION);
      expect(NAVIGATION_PAGES[3]).assertEqual(AppPage.REQUESTS);
      expect(NAVIGATION_PAGES[4]).assertEqual(AppPage.CONNECTIONS);
      expect(NAVIGATION_PAGES[5]).assertEqual(AppPage.SETTINGS);
    });

    it('selectsPagesWithoutCreatingRoutes', 0, () => {
      const navigationState = new AppNavigationState();
      expect(navigationState.selectedPage).assertEqual(AppPage.DASHBOARD);

      navigationState.selectPage(AppPage.CONNECTIONS);
      expect(navigationState.selectedPage).assertEqual(AppPage.CONNECTIONS);

      navigationState.selectPage(AppPage.DASHBOARD);
      expect(navigationState.selectedPage).assertEqual(AppPage.DASHBOARD);
    });

    it('usesCurrentProxyColumns', 0, () => {
      expect(resolveResponsiveMetrics(360).proxyColumns).assertEqual('1fr 1fr');
      expect(resolveResponsiveMetrics(700).proxyColumns).assertEqual('1fr 1fr 1fr 1fr');
      expect(resolveResponsiveMetrics(360, true).proxyColumns).assertEqual('1fr 1fr 1fr 1fr');
      expect(resolveResponsiveMetrics(1000).proxyColumns).assertEqual('1fr 1fr 1fr 1fr');
    });

    it('keepsDashboardCardsEqualHeight', 0, () => {
      expect(resolveResponsiveMetrics(360).dashboardCardHeight)
        .assertEqual(resolveResponsiveMetrics(1000).dashboardCardHeight);
    });
  });
}
