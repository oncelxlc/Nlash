import { describe, expect, it } from '@ohos/hypium';
import {
  AppPage,
  BOTTOM_NAV_PAGES,
  NavigationLayout,
  normalizePage,
  resolveNavigationLayout,
  SIDE_NAV_PAGES
} from '../main/ets/models/NavigationModels';
import { AppNavigationState, AppRoute, resolveAppRoute } from '../main/ets/navigation/AppNavigationState';
import { resolveResponsiveMetrics } from '../main/ets/ui/ResponsiveMetrics';

export default function navigationModelsTest() {
  describe('navigationModels', () => {
    it('usesSideNavigationWhenExpanded', 0, () => {
      expect(resolveNavigationLayout(true, true))
        .assertEqual(NavigationLayout.SIDE);
    });

    it('usesBottomNavigationOnFoldedScreen', 0, () => {
      expect(resolveNavigationLayout(true, false))
        .assertEqual(NavigationLayout.BOTTOM);
    });

    it('alwaysUsesBottomNavigationOnOrdinaryPhone', 0, () => {
      expect(resolveNavigationLayout(false, true))
        .assertEqual(NavigationLayout.BOTTOM);
      expect(resolveNavigationLayout(false, false))
        .assertEqual(NavigationLayout.BOTTOM);
    });

    it('exposesExpectedNavigationItems', 0, () => {
      expect(SIDE_NAV_PAGES.length).assertEqual(6);
      expect(SIDE_NAV_PAGES[3]).assertEqual(AppPage.REQUESTS);
      expect(SIDE_NAV_PAGES[4]).assertEqual(AppPage.CONNECTIONS);
      expect(BOTTOM_NAV_PAGES.length).assertEqual(4);
      expect(BOTTOM_NAV_PAGES[0]).assertEqual(AppPage.DASHBOARD);
      expect(BOTTOM_NAV_PAGES[3]).assertEqual(AppPage.SETTINGS);
    });

    it('preservesHiddenBottomNavigationPages', 0, () => {
      expect(normalizePage(AppPage.REQUESTS, NavigationLayout.BOTTOM)).assertEqual(AppPage.REQUESTS);
      expect(normalizePage(AppPage.CONNECTIONS, NavigationLayout.BOTTOM)).assertEqual(AppPage.CONNECTIONS);
      expect(normalizePage(AppPage.PROXY, NavigationLayout.BOTTOM)).assertEqual(AppPage.PROXY);
    });

    it('mapsPrimaryPagesToRoutes', 0, () => {
      expect(resolveAppRoute(AppPage.DASHBOARD)).assertEqual(AppRoute.DASHBOARD);
      expect(resolveAppRoute(AppPage.PROXY)).assertEqual(AppRoute.PROXY);
      expect(resolveAppRoute(AppPage.CONFIGURATION)).assertEqual(AppRoute.CONFIGURATION);
      expect(resolveAppRoute(AppPage.SETTINGS)).assertEqual(AppRoute.SETTINGS);
    });

    it('keepsPrimaryPagesAtTheSameRouteLevel', 0, () => {
      const navigationState = new AppNavigationState();
      expect(navigationState.pathStack.getAllPathName().length).assertEqual(1);
      expect(navigationState.pathStack.getAllPathName()[0]).assertEqual(AppRoute.DASHBOARD);

      navigationState.selectPage(AppPage.PROXY);
      expect(navigationState.pathStack.getAllPathName().length).assertEqual(1);
      expect(navigationState.pathStack.getAllPathName()[0]).assertEqual(AppRoute.PROXY);

      navigationState.selectPage(AppPage.DASHBOARD);
      expect(navigationState.pathStack.getAllPathName().length).assertEqual(1);
      expect(navigationState.pathStack.getAllPathName()[0]).assertEqual(AppRoute.DASHBOARD);
    });

    it('usesCurrentProxyColumns', 0, () => {
      expect(resolveResponsiveMetrics(360).proxyCardWidth).assertEqual('49%');
      expect(resolveResponsiveMetrics(700).proxyCardWidth).assertEqual('49%');
      expect(resolveResponsiveMetrics(360, true).proxyCardWidth).assertEqual('24%');
      expect(resolveResponsiveMetrics(1000).proxyCardWidth).assertEqual('24%');
    });

    it('keepsDashboardCardsEqualHeight', 0, () => {
      expect(resolveResponsiveMetrics(360).dashboardCardHeight)
        .assertEqual(resolveResponsiveMetrics(1000).dashboardCardHeight);
    });
  });
}
