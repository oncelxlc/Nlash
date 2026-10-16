import { PageHeader } from '../components/PageHeader';
import { textTabBar } from '../components/TextTabBar';
import { CONTROL_HEIGHT } from '../constants/UiConstants';
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
      PageHeader({ title: $r('app.string.nav_activity'), contentPadding: this.metrics.pagePadding })
      Tabs({ index: ACTIVITY_TABS.indexOf(this.selectedTab) }) {
        TabContent() {
          Column() { ConnectionsPage({ query: this.connectionQuery, contentPadding: this.metrics.pagePadding }) }
            .width('100%').height('100%').padding({ top: 8 })
        }
        .tabBar(textTabBar('实时连接'))
        TabContent() {
          Column() {
            RequestsPage({ query: this.requestQuery, filter: this.requestFilter, contentPadding: this.metrics.pagePadding })
          }
          .width('100%').height('100%').padding({ top: 8 })
        }
        .tabBar(textTabBar('请求记录'))
      }
      .barMode(BarMode.Fixed)
      .barHeight(CONTROL_HEIGHT)
      .barBackgroundColor(Color.Transparent)
      .divider(null)
      .scrollable(false)
      .animationDuration(0)
      .cachedMaxCount(0, TabsCacheMode.CACHE_LATEST_SWITCHED)
      .onChange((index: number): void => { this.onTabChange(ACTIVITY_TABS[index]); })
      .width('100%').layoutWeight(1)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_old: Area, area: Area): void => {
      this.metrics = resolveResponsiveMetrics(resolveContentWidth(area.width));
    })
  }
}
