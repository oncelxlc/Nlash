export enum AppPage {
  DASHBOARD,
  PROXY,
  CONFIGURATION,
  REQUESTS,
  CONNECTIONS,
  SETTINGS
}

export enum NavigationLayout {
  SIDE,
  BOTTOM
}

export const SIDE_NAV_PAGES: AppPage[] = [
  AppPage.DASHBOARD,
  AppPage.PROXY,
  AppPage.CONFIGURATION,
  AppPage.REQUESTS,
  AppPage.CONNECTIONS,
  AppPage.SETTINGS
];

export const BOTTOM_NAV_PAGES: AppPage[] = [
  AppPage.DASHBOARD,
  AppPage.PROXY,
  AppPage.CONFIGURATION,
  AppPage.SETTINGS
];

export function resolveNavigationLayout(isFoldable: boolean, isExpanded: boolean): NavigationLayout {
  if (isFoldable && isExpanded) {
    return NavigationLayout.SIDE;
  }
  return NavigationLayout.BOTTOM;
}

export function normalizePage(page: AppPage, _layout: NavigationLayout): AppPage {
  return page;
}
