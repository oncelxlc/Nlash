import { DashboardSnapshot } from '../model/RuntimeModels';
import { formatBytes } from '../utils/RuntimeUtils';

@Component
export struct RuntimeStatusCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 120;

  build() {
    Column({ space: 6 }) {
      Text('运行状态')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .width('100%')
      Text(`${this.runtime?.connectionCount ?? 0} 个活动连接`)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .maxLines(1)
      Text(`Core 内存 ${formatBytes(this.runtime?.memoryBytes ?? 0)}`)
        .fontSize(12)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(2)
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width(this.cardWidth)
    .height(this.cardHeight)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }
}
