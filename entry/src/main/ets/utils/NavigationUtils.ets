import { AppPage, NavigationLayout } from '../model/NavigationModels';

export function resolveNavigationLayout(isFoldable: boolean, isExpanded: boolean,
  isSmallWindow: boolean = false): NavigationLayout {
  if (isFoldable && isExpanded && !isSmallWindow) {
    return NavigationLayout.SIDE;
  }
  return NavigationLayout.BOTTOM;
}

export function normalizePage(page: AppPage, _layout: NavigationLayout): AppPage {
  return page;
}
