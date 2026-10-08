import { PageHeader } from '../components/PageHeader';
import { SingleChoiceControl } from '../components/SingleChoiceControl';
import { ActivityTab, RequestFilter } from '../model/NavigationModels';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveContentWidth, resolveResponsiveMetrics } from '../utils/ResponsiveUtils';
import { ConnectionsPage } from './ConnectionsPage';
import { RequestsPage } from './RequestsPage';

const ACTIVITY_TABS: ActivityTab[] = [ActivityTab.CONNECTIONS, ActivityTab.REQUESTS];

@Component
export struct ActivityPage {
  @Prop selectedTab: ActivityTab = ActivityTab.CONNECTIONS;
  onTabChange: (tab: ActivityTab) => void = (): void => {};
  @State connectionQuery: string = '';
  @State requestQuery: string = '';
  @State requestFilter: RequestFilter = RequestFilter.ALL;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);

  build() {
    Column({ space: 8 }) {
      PageHeader({ title: $r('app.string.nav_activity'), subtitle: '实时连接与本次会话的请求记录' })
      SingleChoiceControl({
        labels: ['实时连接', '请求记录'],
        selectedIndex: ACTIVITY_TABS.indexOf(this.selectedTab),
        accessibilityLabel: '活动内容',
        onChange: (index: number): void => { this.onTabChange(ACTIVITY_TABS[index]); }
      })
      if (this.selectedTab === ActivityTab.CONNECTIONS) {
        ConnectionsPage({ query: this.connectionQuery })
      } else {
        RequestsPage({ query: this.requestQuery, filter: this.requestFilter })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({
      top: this.metrics.pagePadding, left: this.metrics.pagePadding, right: this.metrics.pagePadding
    })
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_old: Area, area: Area): void => {
      this.metrics = resolveResponsiveMetrics(resolveContentWidth(area.width));
    })
  }
}
