import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { EmptyStateBackground } from '../components/EmptyStateBackground';
import { DashboardSnapshot, TrafficSample } from '../model/RuntimeModels';
import { formatSpeed } from '../utils/RuntimeUtils';
import { CoreServiceState, ProxyState } from '../model/VpnModels';
import {
  METRIC_FONT_SIZE, CARD_RADIUS, CAPTION_FONT_SIZE
} from '../constants/UiConstants';

@Component
export struct RuntimeSpeedCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop @Watch('onHistoryChange') history: TrafficSample[] = [];
  @Prop proxyState: ProxyState = ProxyState.DISABLED;
  @Prop coreState: CoreServiceState = CoreServiceState.STOPPED;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 216;
  @State chartUnavailable: boolean = false;
  private chartSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private chartContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.chartSettings);
  private chartWidth: number = 0;
  private chartHeight: number = 88;
  private themeRedrawTimer: number | undefined = undefined;
  private applicationContext: common.ApplicationContext | undefined = undefined;
  private environmentCallbackId: number | undefined = undefined;

  aboutToAppear(): void {
    this.applicationContext = this.getUIContext().getHostContext()?.getApplicationContext();
    try {
      this.environmentCallbackId = this.applicationContext?.on('environment', {
        onConfigurationUpdated: (): void => { this.scheduleThemeRedraw(); },
        onMemoryLevel: (): void => {}
      });
    } catch (error) {
      hilog.warn(0x0000, 'RuntimeSpeedCard', 'Cannot observe chart configuration: %{public}s', String(error));
    }
  }

  onWillApplyTheme(_theme: Theme): void {
    this.scheduleThemeRedraw();
  }

  private scheduleThemeRedraw(): void {
    if (this.applicationContext === undefined) { return; }
    if (this.themeRedrawTimer !== undefined) { clearTimeout(this.themeRedrawTimer); }
    this.themeRedrawTimer = setTimeout((): void => {
      this.themeRedrawTimer = undefined;
      this.drawTrafficChart();
    }, 0);
  }

  aboutToDisappear(): void {
    if (this.themeRedrawTimer !== undefined) {
      clearTimeout(this.themeRedrawTimer);
      this.themeRedrawTimer = undefined;
    }
    if (this.environmentCallbackId !== undefined) {
      try {
        this.applicationContext?.off('environment', this.environmentCallbackId).catch((error: Error): void => {
          hilog.warn(0x0000, 'RuntimeSpeedCard', 'Cannot release chart configuration observer: %{public}s', error.message);
        });
      } catch (error) {
        hilog.warn(0x0000, 'RuntimeSpeedCard', 'Cannot release chart configuration observer: %{public}s', String(error));
      }
      this.environmentCallbackId = undefined;
    }
    this.applicationContext = undefined;
  }

  private onHistoryChange(): void {
    this.drawTrafficChart();
  }

  private hasTrafficData(): boolean {
    return this.history.some((sample: TrafficSample): boolean =>
      sample.uploadSpeed > 0 || sample.downloadSpeed > 0);
  }

  private drawTrafficChart(): void {
    if (this.chartWidth <= 0) { return; }
    try {
      const resources = this.getUIContext().getHostContext()?.resourceManager;
      if (resources === undefined) { throw new Error('Chart UI context is unavailable'); }
      const grid = `#${(resources.getColorByNameSync('chart_grid') & 0xFFFFFF).toString(16).padStart(6, '0')}`;
      const download = `#${(resources.getColorByNameSync('chart_download') & 0xFFFFFF).toString(16).padStart(6, '0')}`;
      const upload = `#${(resources.getColorByNameSync('chart_upload') & 0xFFFFFF).toString(16).padStart(6, '0')}`;
      const context = this.chartContext;
      context.clearRect(0, 0, this.chartWidth, this.chartHeight);
      context.strokeStyle = grid;
      context.lineWidth = 1;
      for (let line = 1; line <= 3; line++) {
        const y = (this.chartHeight - 8) * line / 3;
        context.beginPath();
        context.moveTo(0, y);
        context.lineTo(this.chartWidth, y);
        context.stroke();
      }
      let maximum = 1;
      this.history.forEach((sample: TrafficSample): void => {
        maximum = Math.max(maximum, sample.uploadSpeed, sample.downloadSpeed);
      });
      this.drawTrafficLine(false, maximum, download);
      this.drawTrafficLine(true, maximum, upload);
      this.chartUnavailable = false;
    } catch (error) {
      if (!this.chartUnavailable) {
        hilog.warn(0x0000, 'RuntimeSpeedCard', 'Traffic chart unavailable: %{public}s', String(error));
      }
      this.chartUnavailable = true;
    }
  }

  private drawTrafficLine(upload: boolean, maximum: number, color: string): void {
    if (this.history.length === 0) { return; }
    const context = this.chartContext;
    context.beginPath();
    const latestTimestamp = this.history[this.history.length - 1].timestamp;
    const earliestTimestamp = latestTimestamp - 60000;
    this.history.forEach((sample: TrafficSample, index: number): void => {
      const x = this.history.length === 1 ? this.chartWidth :
        Math.max(0, sample.timestamp - earliestTimestamp) * this.chartWidth / 60000;
      const value = upload ? sample.uploadSpeed : sample.downloadSpeed;
      const y = this.chartHeight - 8 - (value / maximum) * (this.chartHeight - 20);
      if (index === 0) { context.moveTo(x, y); } else { context.lineTo(x, y); }
    });
    context.strokeStyle = color;
    context.lineWidth = 2;
    context.stroke();
  }

  @Builder
  private speedValue(label: string, speed: number | undefined, color: ResourceColor) {
    Column({ space: 4 }) {
      Text(label).fontSize(CAPTION_FONT_SIZE).fontColor(color)
      Text(speed === undefined ? '—' : formatSpeed(speed))
        .fontSize(METRIC_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .maxLines(1)
        .minFontSize(20)
        .maxFontSize(METRIC_FONT_SIZE)
        .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
    }
    .alignItems(HorizontalAlign.Start)
    .layoutWeight(1)
  }

  build() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        this.speedValue('↑ 上传 / 秒', this.runtime?.uploadSpeed, $r('app.color.chart_upload'))
        this.speedValue('↓ 下载 / 秒', this.runtime?.downloadSpeed, $r('app.color.chart_download'))
      }
      .width('100%')
      Stack({ alignContent: Alignment.Center }) {
        if (this.proxyState !== ProxyState.ENABLED || this.chartUnavailable || !this.hasTrafficData()) {
          EmptyStateBackground({
            compact: true,
            title: this.proxyState !== ProxyState.ENABLED ? '代理未连接，流量统计已暂停' :
              (this.chartUnavailable ? '图表暂不可用，实时数值仍会更新' : '正在等待网络流量')
          })
        }
        Canvas(this.chartContext)
          .width('100%')
          .height('100%')
          .onReady((): void => this.drawTrafficChart())
          .onAreaChange((_old: Area, area: Area): void => {
            const width = Number(area.width);
            const height = Number(area.height);
            this.chartWidth = Number.isFinite(width) ? width : 0;
            this.chartHeight = Number.isFinite(height) && height > 0 ? height : this.chartHeight;
            this.drawTrafficChart();
          })
          .accessibilityText(`最近 60 秒速度趋势。当前上传 ${formatSpeed(this.runtime?.uploadSpeed ?? 0)}，下载 ${formatSpeed(this.runtime?.downloadSpeed ?? 0)}`)
          .opacity(this.proxyState !== ProxyState.ENABLED || this.chartUnavailable || !this.hasTrafficData() ? 0 : 1)
          .blur(this.proxyState !== ProxyState.ENABLED || this.chartUnavailable || !this.hasTrafficData() ? 0 : 0)
      }
      .width('100%')
      .height(Math.max(88, this.cardHeight - 128))
      .width('100%')
      .accessibilityLevel('no')
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.cardWidth)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
  }
}
