import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { LengthMetrics } from '@kit.ArkUI';
import { CAPTION_FONT_SIZE } from '../constants/UiConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { buildTrafficDonutPath, formatBytes, formatBytesParts } from '../utils/RuntimeUtils';

interface TrafficTotalParams {
  label: string;
  value: number | undefined;
  color: ResourceColor;
}

/** 上传/下载累计量及比例展示，缺失快照与真实零流量分别显示。 */
@Component
export struct RuntimeTrafficCard {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 188;

  // Path 命令使用像素坐标，先把固定 64vp 的绘图区转换到当前设备像素。
  private donutPath(isUpload: boolean): string {
    return buildTrafficDonutPath(this.runtime?.uploadTotal ?? 0, this.runtime?.downloadTotal ?? 0,
      isUpload, this.getUIContext().vp2px(64));
  }

  @Builder
  private legend(label: string, color: ResourceColor) {
    Row({ space: 6 }) {
      Rect().width(16).height(6).radius(3).fill(color).accessibilityLevel('no')
      Text(label).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_primary'))
    }
  }

  @Builder
  private donut() {
    Stack() {
      if ((this.runtime?.uploadTotal ?? 0) <= 0 && (this.runtime?.downloadTotal ?? 0) <= 0) {
        Circle().width(56).height(56).fill(Color.Transparent)
          .stroke(this.theme.divider).strokeWidth(7.5)
      } else {
        Path().commands(this.donutPath(true)).width(64).height(64)
          .fill(Color.Transparent).stroke(this.theme.accent)
          .strokeWidth(7.5).strokeLineCap(LineCapStyle.Round)
        Path().commands(this.donutPath(false)).width(64).height(64)
          .fill(Color.Transparent).stroke(this.theme.accentSecondary)
          .strokeWidth(7.5).strokeLineCap(LineCapStyle.Round)
      }
    }
    .width(64).height(64).flexShrink(0)
    .accessibilityLevel('no')
  }

  @Builder
  private total($$: TrafficTotalParams) {
    Row({ space: 8 }) {
      Text($$.label === '上传' ? '↑' : '↓').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($$.color)
        .accessibilityLevel('no')
      Text($$.value === undefined ? '—' : formatBytesParts($$.value).value)
        .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily || 'monospace')
        .fontColor($r('app.color.content_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
      Text($$.value === undefined ? '' : formatBytesParts($$.value).unit)
        .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
    }
    .width('100%')
    .accessibilityGroup(true)
    .accessibilityText(`${$$.label} ${$$.value === undefined ? '数据暂不可用' : formatBytes($$.value)}`)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.traffic_statistics')).width(16).height(16)
          .fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
        Text('流量统计').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_secondary'))
      }
      .constraintSize({ minHeight: 20 })
      Flex({
        wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Start,
        space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(8) }
      }) {
        this.donut()
        Column({ space: 8 }) {
          this.legend('上传', this.theme.accent)
          this.legend('下载', this.theme.accentSecondary)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      Column({ space: 8 }) {
        this.total({ label: '上传', value: this.runtime?.uploadTotal, color: this.theme.accent })
        this.total({ label: '下载', value: this.runtime?.downloadTotal, color: this.theme.accentSecondary })
      }
      .width('100%')
    }
    .width(this.cardWidth)
    .constraintSize({ minHeight: this.cardHeight })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(12)
    .borderRadius(28)
    .border({ width: 1, color: this.theme.divider })
    .backgroundColor(this.theme.surface)
    .accessibilityGroup(true)
    .accessibilityDescription('圆环展示累计上传与下载流量的占比，下方分别列出数值与单位')
  }
}
