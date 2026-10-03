import {
  CARD_RADIUS, CAPTION_FONT_SIZE
} from '../constants/UiConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { formatBytes } from '../utils/RuntimeUtils';
import { AppPage } from '../model/NavigationModels';
import { navigationIntentService } from '../services/NavigationIntentService';

@Component
export struct RuntimeStatusCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 120;

  build() {
    Row({ space: 16 }) {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 6 }) {
          Text('活动连接').fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
          Row({ space: 8 }) {
            Text(this.runtime === undefined ? '—' : `${this.runtime.connectionCount} 个`)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.nav_selected'))
            Image($r('app.media.action_chevron_down'))
              .width(16).height(16).rotate({ angle: -90 }).fillColor($r('app.color.nav_selected'))
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: 48 })
      .padding(0)
      .borderRadius(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText('查看实时连接')
      .onClick((): void => { navigationIntentService.publish(AppPage.CONNECTIONS); })
      Column({ space: 6 }) {
        Text('Core 内存').fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
        Text(this.runtime === undefined ? '—' : formatBytes(this.runtime.memoryBytes))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width(this.cardWidth)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
  }
}
