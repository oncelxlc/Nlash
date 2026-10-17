import {
  CARD_RADIUS, CAPTION_FONT_SIZE
} from '../constants/UiConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { AppPage } from '../model/NavigationModels';
import { navigationIntentService } from '../services/NavigationIntentService';

@Component
export struct RuntimeStatusCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 88;

  build() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Image($r('app.media.nav_connections'))
            .width(16).height(16).fillColor($r('app.color.content_secondary'))
            .accessibilityLevel('no')
          Text('活动连接').fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_secondary'))
        }
        .constraintSize({ minHeight: 20 })
        Row({ space: 8 }) {
          Text(this.runtime === undefined ? '—' : `${this.runtime.connectionCount} 个`)
            .fontSize(20)
            .fontFamily('monospace')
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.nav_selected'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Image($r('app.media.action_chevron_down'))
            .width(16).height(16).rotate({ angle: -90 }).fillColor($r('app.color.nav_selected'))
            .accessibilityLevel('no')
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
      .width('100%')
      .constraintSize({ minHeight: this.cardHeight })
      .padding(12)
    }
    .width(this.cardWidth)
    .padding(0)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .accessibilityText(this.runtime === undefined ? '活动连接数据暂不可用，查看实时连接' :
      `活动连接 ${this.runtime.connectionCount} 个，查看实时连接`)
    .onClick((): void => { navigationIntentService.publish(AppPage.CONNECTIONS); })
  }
}
