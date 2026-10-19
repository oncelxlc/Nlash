import { DASHBOARD_CARD_RADIUS, DASHBOARD_CARD_PADDING } from '../constants/DashboardConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { formatBytesParts } from '../utils/RuntimeUtils';

/** 展示 Core 快照中的内存统计值，快照缺失时保留占位符。 */
@Component
export struct RuntimeMemoryCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardHeight: number = 88;

  build() {
    Column({ space: 16 }) {
      Row({ space: 8 }) {
        Image($r('app.media.runtime_memory'))
          .width(18).height(18).fillColor($r('app.color.content_secondary'))
          .accessibilityLevel('no')
        Text('内存信息').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
      }
      .constraintSize({ minHeight: 20 })
      Text() {
        Span(this.runtime === undefined ? '—' : formatBytesParts(this.runtime.memoryBytes).value)
          .fontSize(32).fontWeight(FontWeight.Bold)
        Span(this.runtime === undefined ? '' : ` ${formatBytesParts(this.runtime.memoryBytes).unit}`).fontSize(14)
      }
        .fontColor($r('app.color.content_primary'))
        .maxLines(2)
      Row({ space: 8 }) {
        Row().width(8).height(8).borderRadius(4).backgroundColor($r('app.color.dashboard_accent')).accessibilityLevel('no')
        Text(this.runtime === undefined ? 'Core 未提供内存数据' : 'Core 实时内存')
          .fontSize(12).fontColor($r('app.color.content_secondary'))
      }
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .constraintSize({ minHeight: this.cardHeight })
    .padding(DASHBOARD_CARD_PADDING)
    .borderRadius(DASHBOARD_CARD_RADIUS)
    .backgroundColor($r('app.color.dashboard_surface'))
    .accessibilityGroup(true)
  }
}
