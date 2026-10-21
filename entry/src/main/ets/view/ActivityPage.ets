import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME } from '../utils/ThemeUtils';
import { ActivityTab, AppPage, RequestFilter } from '../model/NavigationModels';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveContentWidth, resolveResponsiveMetrics } from '../utils/ResponsiveUtils';
import { ConnectionsPage } from './ConnectionsPage';
import { RequestsPage } from './RequestsPage';
import { DnsQueriesPage } from './DnsQueriesPage';
import { ResourcesPage } from './ResourcesPage';

/** 二级页共用响应式边距，兼容旧活动页跳转目标。 */
@Component
export struct ActivityPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop page: AppPage = AppPage.ACTIVITY;
  @Prop selectedTab: ActivityTab = ActivityTab.CONNECTIONS;
  onBack: () => void = (): void => {};
  @State connectionQuery: string = '';
  @State requestQuery: string = '';
  @State requestFilter: RequestFilter = RequestFilter.ALL;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);

  build() {
    Column() {
      if (this.page === AppPage.DNS) {
        DnsQueriesPage({ contentPadding: this.metrics.pagePadding, onBack: this.onBack })
      } else if (this.page === AppPage.RESOURCES) {
        ResourcesPage({ contentPadding: this.metrics.pagePadding, onBack: this.onBack })
      } else if (this.page === AppPage.REQUESTS ||
        (this.page === AppPage.ACTIVITY && this.selectedTab === ActivityTab.REQUESTS)) {
        RequestsPage({ query: this.requestQuery, filter: this.requestFilter,
          contentPadding: this.metrics.pagePadding, onBack: this.onBack })
      } else {
        ConnectionsPage({ query: this.connectionQuery, contentPadding: this.metrics.pagePadding, onBack: this.onBack })
      }
    }
    .width('100%').height('100%').backgroundColor(this.theme.background)
    .onAreaChange((_old: Area, area: Area): void => {
      this.metrics = resolveResponsiveMetrics(resolveContentWidth(area.width));
    })
  }
}
