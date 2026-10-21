import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { DASHBOARD_CARD_RADIUS } from '../constants/DashboardConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { AppPage } from '../model/NavigationModels';
import { navigationIntentService } from '../services/NavigationIntentService';

/** 当前连接和有限请求历史分别进入活动页的对应标签。 */
@Component
export struct RuntimeStatusCard {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop requestCount: number = 0;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 88;

  @Builder
  private metric(value: string, label: string, page: AppPage) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 6 }) {
        Text(value).fontSize(themeFontSize(26, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold).fontColor($r('app.color.content_primary'))
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(label).fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
      }
      .width('100%').padding({ top: 16, bottom: 16 })
    }
    .layoutWeight(1).padding(0).borderRadius(24).backgroundColor(Color.Transparent)
    .accessibilityText(`${label} ${value === '—' ? '数据暂不可用' : value}，打开活动页`)
    .onClick((): void => { navigationIntentService.publish(page); })
  }

  build() {
    Row({ space: 8 }) {
      this.metric(this.runtime === undefined ? '—' : `${this.runtime.connectionCount}`, '实时连接', AppPage.CONNECTIONS)
      this.metric(`${this.requestCount}`, '最近请求', AppPage.REQUESTS)
    }
    .width(this.cardWidth).constraintSize({ minHeight: this.cardHeight }).padding(8)
    .borderRadius(DASHBOARD_CARD_RADIUS).backgroundColor(this.theme.surface)
  }
}
