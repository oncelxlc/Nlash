import { DashboardSnapshot, TrafficSample } from '../model/RuntimeModels';
import { formatSpeed } from '../utils/RuntimeUtils';
import { CoreServiceState, ProxyState } from '../model/VpnModels';

@Component
export struct RuntimeSpeedCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop @Watch('onHistoryChange') history: TrafficSample[] = [];
  @Prop proxyState: ProxyState = ProxyState.DISABLED;
  @Prop coreState: CoreServiceState = CoreServiceState.STOPPED;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 320;
  private chartSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private chartContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.chartSettings);
  private chartWidth: number = 0;
  private chartHeight: number = 320;

  private onHistoryChange(): void {
    setTimeout((): void => this.drawTrafficChart(), 0);
  }

  private hasTrafficData(): boolean {
    return this.history.some((sample: TrafficSample): boolean =>
      sample.uploadSpeed > 0 || sample.downloadSpeed > 0);
  }

  private drawTrafficChart(): void {
    if (this.chartWidth <= 0) {
      return;
    }
    const context = this.chartContext;
    context.clearRect(0, 0, this.chartWidth, this.chartHeight);
    let maximum = 1;
    this.history.forEach((sample: TrafficSample): void => {
      maximum = Math.max(maximum, sample.uploadSpeed, sample.downloadSpeed);
    });
    this.drawTrafficLine(false, maximum, '#6EC8FF');
    this.drawTrafficLine(true, maximum, '#7BE0A3');
  }

  private drawTrafficLine(upload: boolean, maximum: number, color: string): void {
    if (this.history.length === 0) {
      return;
    }
    const context = this.chartContext;
    context.beginPath();
    const latestTimestamp = this.history[this.history.length - 1].timestamp;
    const earliestTimestamp = latestTimestamp - 60000;
    this.history.forEach((sample: TrafficSample, index: number): void => {
      const x = this.history.length === 1 ? this.chartWidth :
        Math.max(0, sample.timestamp - earliestTimestamp) * this.chartWidth / 60000;
      const value = upload ? sample.uploadSpeed : sample.downloadSpeed;
      const y = this.chartHeight - 8 - (value / maximum) * (this.chartHeight - 20);
      if (index === 0) {
        context.moveTo(x, y);
      } else {
        context.lineTo(x, y);
      }
    });
    context.strokeStyle = color;
    context.lineWidth = 2;
    context.stroke();
  }

  build() {
    Column({ space: 10 }) {
      Row() {
        Text('网络速度 · 最近 60 秒')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
          .width('100%')
        Text(`↑ ${formatSpeed(this.runtime?.uploadSpeed ?? 0)}  ↓ ${formatSpeed(this.runtime?.downloadSpeed ?? 0)}`)
          .fontSize(11)
          .fontColor($r('app.color.content_secondary'))
          .position({ top: 0, right: 0 })
      }
      .width('100%')
      Stack({ alignContent: Alignment.Center }) {
        Canvas(this.chartContext)
          .width('100%')
          .height('100%')
          .onReady((): void => this.drawTrafficChart())
          .onAreaChange((_oldValue: Area, newValue: Area): void => {
            const width = typeof newValue.width === 'number' ? newValue.width : Number(newValue.width);
            const height = typeof newValue.height === 'number' ? newValue.height : Number(newValue.height);
            this.chartWidth = Number.isFinite(width) ? width : 0;
            this.chartHeight = Number.isFinite(height) && height > 0 ? height : this.chartHeight;
            this.drawTrafficChart();
          })
        if (!this.hasTrafficData()) {
          Column({ space: 5 }) {
            Text('暂无速度数据')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.content_secondary'))
            Text(this.proxyState === ProxyState.ENABLED ? '正在等待网络流量' :
              (this.coreState === CoreServiceState.RUNNING ? '代理已关闭，系统流量直连' : 'Core 就绪后显示运行数据'))
              .fontSize(12)
              .fontColor($r('app.color.content_secondary'))
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.cardWidth)
    .height(this.cardHeight)
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }
}
