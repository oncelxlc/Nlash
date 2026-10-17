import { CAPTION_FONT_SIZE, CARD_RADIUS } from '../constants/UiConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { formatBytes } from '../utils/RuntimeUtils';

@Component
export struct RuntimeMemoryCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardHeight: number = 88;

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image($r('app.media.runtime_memory'))
          .width(16).height(16).fillColor($r('app.color.content_secondary'))
          .accessibilityLevel('no')
        Text('Core 内存').fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_secondary'))
      }
      .constraintSize({ minHeight: 20 })
      Text(this.runtime === undefined ? '—' : formatBytes(this.runtime.memoryBytes))
        .fontSize(20).fontFamily('monospace').fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .constraintSize({ minHeight: this.cardHeight })
    .padding(12)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .accessibilityGroup(true)
  }
}
