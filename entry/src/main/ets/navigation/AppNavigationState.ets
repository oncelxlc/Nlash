import { ActivityTab, AppPage } from '../model/NavigationModels';

/** 设置二级页保留一级页面状态，并兼容已有卡片和通知的跳转目标。 */
@Observed
export class AppNavigationState {
  selectedPage: AppPage = AppPage.DASHBOARD;
  activityOpen: boolean = false;
  activityTab: ActivityTab = ActivityTab.CONNECTIONS;
  detailPage: AppPage = AppPage.CONNECTIONS;

  /** 兼容卡片或通知发出的旧页面目标，集中转换为现有导航结构。 */
  selectPage(page: AppPage): void {
    if (page === AppPage.REQUESTS || page === AppPage.CONNECTIONS || page === AppPage.DNS ||
      page === AppPage.RESOURCES || page === AppPage.THEME || page === AppPage.GENERAL) {
      this.detailPage = page;
      if (page === AppPage.REQUESTS || page === AppPage.CONNECTIONS) {
        this.activityTab = page === AppPage.REQUESTS ? ActivityTab.REQUESTS : ActivityTab.CONNECTIONS;
      }
      this.activityOpen = true;
      this.selectedPage = AppPage.SETTINGS;
    } else {
      this.activityOpen = page === AppPage.ACTIVITY;
      if (this.activityOpen) {
        this.detailPage = this.activityTab === ActivityTab.REQUESTS ? AppPage.REQUESTS : AppPage.CONNECTIONS;
      }
      this.selectedPage = this.activityOpen ? AppPage.SETTINGS : page;
    }
  }

  selectActivityTab(tab: ActivityTab): void {
    this.activityTab = tab;
    this.selectPage(AppPage.ACTIVITY);
  }
}
