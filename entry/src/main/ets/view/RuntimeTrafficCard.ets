import {
  CARD_RADIUS, CAPTION_FONT_SIZE, BODY_FONT_SIZE
} from '../constants/UiConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { formatBytes } from '../utils/RuntimeUtils';

interface TrafficTotalParams {
  label: string;
  value: number | undefined;
  color: ResourceColor;
}

@Component
export struct RuntimeTrafficCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 96;

  @Builder
  private total($$: TrafficTotalParams) {
    Row({ space: 8 }) {
      Text($$.label).fontSize(CAPTION_FONT_SIZE).fontColor($$.color)
      Text($$.value === undefined ? '—' : formatBytes($$.value))
        .fontSize(BODY_FONT_SIZE)
        .fontFamily('monospace')
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)
    }
    .width('100%')
  }

  build() {
    Column({ space: 8 }) {
      Text('累计流量').fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_secondary')).constraintSize({ minHeight: 20 })
      Column({ space: 4 }) {
        this.total({ label: '上传', value: this.runtime?.uploadTotal, color: $r('app.color.chart_upload') })
        this.total({ label: '下载', value: this.runtime?.downloadTotal, color: $r('app.color.chart_download') })
      }
      .width('100%')
    }
    .width(this.cardWidth)
    .constraintSize({ minHeight: this.cardHeight })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(12)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .accessibilityGroup(true)
  }
}
