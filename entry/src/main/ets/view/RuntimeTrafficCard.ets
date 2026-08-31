import { DashboardSnapshot } from '../model/RuntimeModels';
import { formatBytesParts } from '../utils/RuntimeUtils';

@Component
export struct RuntimeTrafficCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 120;

  build() {
    Column({ space: 8 }) {
      Text('流量统计')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .width('100%')
      Row({ space: 14 }) {
        DataPanel({
          values: [this.runtime?.uploadTotal ?? 0, this.runtime?.downloadTotal ?? 0],
          max: Math.max(1, (this.runtime?.uploadTotal ?? 0) + (this.runtime?.downloadTotal ?? 0)),
          type: DataPanelType.Circle
        })
          .valueColors(['#65ffe600', '#650099ff'])
          .width(80)
          .height(80)
          .strokeWidth(10)
          .closeEffect(true)
        Column({ space: 7 }) {
          Row({ space: 0 }) {
            Text('上传')
            Text(formatBytesParts(this.runtime?.uploadTotal ?? 0).value)
              .width('40%')
              .textAlign(TextAlign.End)
            Text(formatBytesParts(this.runtime?.uploadTotal ?? 0).unit)
              .padding({ left: '5%', right: '5%' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Start)
          Row({ space: 0 }) {
            Text('下载')
            Text(formatBytesParts(this.runtime?.downloadTotal ?? 0).value)
              .width('40%')
              .textAlign(TextAlign.End)
            Text(formatBytesParts(this.runtime?.downloadTotal ?? 0).unit)
              .padding({ left: '5%', right: '5%' })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .flexGrow(1)
        .layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.cardWidth)
    .height(this.cardHeight)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }
}
