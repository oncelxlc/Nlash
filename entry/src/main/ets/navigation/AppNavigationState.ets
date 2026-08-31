import { AppPage } from '../model/NavigationModels';

export enum AppRoute {
  DASHBOARD = 'page/dashboard',
  PROXY = 'page/proxy',
  CONFIGURATION = 'page/configuration',
  REQUESTS = 'page/requests',
  CONNECTIONS = 'page/connections',
  SETTINGS = 'page/settings'
}

export function resolveAppRoute(page: AppPage): AppRoute | undefined {
  switch (page) {
    case AppPage.DASHBOARD:
      return AppRoute.DASHBOARD;
    case AppPage.PROXY:
      return AppRoute.PROXY;
    case AppPage.CONFIGURATION:
      return AppRoute.CONFIGURATION;
    case AppPage.REQUESTS:
      return AppRoute.REQUESTS;
    case AppPage.CONNECTIONS:
      return AppRoute.CONNECTIONS;
    case AppPage.SETTINGS:
      return AppRoute.SETTINGS;
    default:
      return undefined;
  }
}

@Observed
export class AppNavigationState {
  selectedPage: AppPage = AppPage.DASHBOARD;
  readonly pathStack: NavPathStack = new NavPathStack();

  constructor() {
    this.pathStack.pushPathByName(AppRoute.DASHBOARD, '', false);
  }

  selectPage(page: AppPage): void {
    const route = resolveAppRoute(page);
    if (route === undefined) {
      return;
    }
    const paths = this.pathStack.getAllPathName();
    if (paths.length === 1 && paths[0] === route) {
      this.selectedPage = page;
      return;
    }
    this.selectedPage = page;
    if (paths.length === 0) {
      this.pathStack.pushPathByName(route, '', true);
    } else if (paths.length === 1) {
      this.pathStack.replacePathByName(route, '', true);
    } else {
      this.pathStack.clear(false);
      this.pathStack.pushPathByName(route, '', true);
    }
  }
}
