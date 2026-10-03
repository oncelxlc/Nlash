import { ActivityTab, AppPage } from '../model/NavigationModels';

@Observed
export class AppNavigationState {
  selectedPage: AppPage = AppPage.DASHBOARD;
  activityTab: ActivityTab = ActivityTab.CONNECTIONS;

  selectPage(page: AppPage): void {
    if (page === AppPage.REQUESTS || page === AppPage.CONNECTIONS) {
      this.selectActivityTab(page === AppPage.REQUESTS ? ActivityTab.REQUESTS : ActivityTab.CONNECTIONS);
    } else {
      this.selectedPage = page;
    }
  }

  selectActivityTab(tab: ActivityTab): void {
    this.activityTab = tab;
    this.selectedPage = AppPage.ACTIVITY;
  }
}
