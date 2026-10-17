import { ActivityTab, AppPage } from '../model/NavigationModels';

/** 请求与连接的跳转统一落到活动页，并保留对应子标签的选择。 */
@Observed
export class AppNavigationState {
  selectedPage: AppPage = AppPage.DASHBOARD;
  activityTab: ActivityTab = ActivityTab.CONNECTIONS;

  /** 兼容卡片或通知发出的旧页面目标，集中转换为现有导航结构。 */
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
