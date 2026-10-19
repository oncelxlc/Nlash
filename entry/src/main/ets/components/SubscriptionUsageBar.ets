import { buildSubscriptionUsageWave } from '../utils/DashboardUtils';

/** 已用部分绘制静态波浪，剩余部分为灰色轨道，具体数值由配置卡展示。 */
@Component
export struct SubscriptionUsageBar {
  @Prop ratio: number = 0;
  @State barWidth: number = 0;

  private usedRatio(): number {
    return Number.isFinite(this.ratio) ? Math.min(1, Math.max(0, this.ratio)) : 0;
  }

  build() {
    Stack({ alignContent: Alignment.Start }) {
      if (this.usedRatio() < 1) {
        Row().width(Math.max(0, (this.barWidth - 12) * (1 - this.usedRatio()) - 8)).height(4)
          .backgroundColor($r('app.color.dashboard_track')).borderRadius(2)
          .position({ x: (this.barWidth - 12) * this.usedRatio() + 8, y: 4 })
      }
      Path().commands(buildSubscriptionUsageWave(this.getUIContext().vp2px(Math.max(0, this.barWidth - 12)),
        this.getUIContext().vp2px(12), this.usedRatio()))
        .width('100%').height(12).fill(Color.Transparent).stroke($r('app.color.dashboard_accent'))
        .strokeWidth(3.5).strokeLineCap(LineCapStyle.Round)
      Row().width(4).height(4).borderRadius(2).backgroundColor($r('app.color.dashboard_accent'))
        .position({ x: Math.max(0, this.barWidth - 4), y: 4 })
    }
    .width('100%').height(12).accessibilityLevel('no')
    .onAreaChange((_old: Area, area: Area): void => { this.barWidth = Number(area.width); })
  }
}
