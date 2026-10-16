import {
  CARD_RADIUS, CAPTION_FONT_SIZE
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
  @Prop cardHeight: number = 120;

  @Builder
  private total($$: TrafficTotalParams) {
    Column({ space: 6 }) {
      Text($$.label).fontSize(CAPTION_FONT_SIZE).fontColor($$.color)
      Text($$.value === undefined ? '—' : formatBytes($$.value))
        .fontSize(24)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  build() {
    Row({ space: 16 }) {
      this.total({ label: '累计上传', value: this.runtime?.uploadTotal, color: $r('app.color.chart_upload') })
      this.total({ label: '累计下载', value: this.runtime?.downloadTotal, color: $r('app.color.chart_download') })
    }
    .width(this.cardWidth)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
  }
}
