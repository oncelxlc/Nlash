import { CAPTION_FONT_SIZE, CARD_RADIUS } from '../constants/UiConstants';
import { formatVpnRunDuration } from '../utils/VpnUtils';

/** 只格式化父页传入的秒数，单调时钟计算与会话状态由宿主和仪表盘统一维护。 */
@Component
export struct RuntimeDurationCard {
  @Prop elapsedSeconds: number = 0;
  @Prop hasSession: boolean = false;
  @Prop cardHeight: number = 88;

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image($r('app.media.runtime_duration'))
          .width(16).height(16).fillColor($r('app.color.content_secondary'))
          .accessibilityLevel('no')
        Text('运行时长').fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_secondary'))
      }
      .constraintSize({ minHeight: 20 })
      Stack({ alignContent: Alignment.Start }) {
        // 隐藏占位文本仍参与布局，防止无会话占位符与计时文本切换时高度跳变。
        Text('00:00:00').fontSize(20).fontFamily('monospace').fontWeight(FontWeight.Medium).maxLines(1)
          .visibility(Visibility.Hidden).accessibilityLevel('no')
        Text(this.hasSession ? formatVpnRunDuration(this.elapsedSeconds) : '—')
          .fontSize(20).fontFamily('monospace').fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
          .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .width('100%')
    .constraintSize({ minHeight: this.cardHeight })
    .padding(12)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .accessibilityGroup(true)
    .accessibilityText(this.hasSession ? `本次运行时长 ${formatVpnRunDuration(this.elapsedSeconds)}` : '尚未开始代理连接')
  }
}
