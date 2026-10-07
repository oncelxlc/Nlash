import { PageHeader } from '../components/PageHeader';
import { ActivityTab, RequestFilter } from '../model/NavigationModels';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveContentWidth, resolveResponsiveMetrics } from '../utils/ResponsiveUtils';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, CARD_RADIUS, BODY_FONT_SIZE
} from '../constants/UiConstants';
import { ConnectionsPage } from './ConnectionsPage';
import { RequestsPage } from './RequestsPage';

@Component
export struct ActivityPage {
  @Prop selectedTab: ActivityTab = ActivityTab.CONNECTIONS;
  onTabChange: (tab: ActivityTab) => void = (): void => {};
  @State connectionQuery: string = '';
  @State requestQuery: string = '';
  @State requestFilter: RequestFilter = RequestFilter.ALL;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);

  @Builder
  private tabButton(label: string, tab: ActivityTab) {
    Button(label)
      .type(ButtonType.Normal)
      .height(CONTROL_HEIGHT)
      .layoutWeight(1)
      .borderRadius(BUTTON_RADIUS)
      .fontSize(BODY_FONT_SIZE)
      .fontWeight(this.selectedTab === tab ? FontWeight.Medium : FontWeight.Normal)
      .fontColor(this.selectedTab === tab ? $r('app.color.nav_selected') : $r('app.color.content_secondary'))
      .backgroundColor(this.selectedTab === tab ? $r('app.color.card_background') : Color.Transparent)
      .accessibilitySelected(this.selectedTab === tab)
      .onClick((): void => { this.onTabChange(tab); })
  }

  build() {
    Column({ space: 16 }) {
      PageHeader({ title: $r('app.string.nav_activity'), subtitle: '实时连接与本次会话的请求记录' })
      Row({ space: 4 }) {
        this.tabButton('实时连接', ActivityTab.CONNECTIONS)
        this.tabButton('请求记录', ActivityTab.REQUESTS)
      }
      .padding(4)
      .borderRadius(CARD_RADIUS)
      .backgroundColor($r('app.color.surface_muted'))
      .width('100%')
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
