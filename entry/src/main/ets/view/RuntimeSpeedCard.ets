import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { DashboardSnapshot, TrafficSample } from '../model/RuntimeModels';
import { buildTrafficChartPoints, formatSpeed, formatBytes, formatBytesParts } from '../utils/RuntimeUtils';
import { ProxyState } from '../model/VpnModels';
import { DASHBOARD_CARD_RADIUS } from '../constants/DashboardConstants';

/** 按方向绘制最近一分钟速度；曲线不可用时仍保留实时数值。 */
@Component
export struct RuntimeSpeedCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop @Watch('onHistoryChange') history: TrafficSample[] = [];
  @Prop proxyState: ProxyState = ProxyState.DISABLED;
  @Prop upload: boolean = true;
  @Prop compact: boolean = true;
  @Prop cardWidth: Length = '100%';
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

  // Canvas 不会自动重绘既有像素，主题应用后下一轮再读取资源色并重新绘制。
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
      (this.upload ? sample.uploadSpeed : sample.downloadSpeed) > 0);
  }

  private drawTrafficChart(): void {
    if (this.chartWidth <= 0) { return; }
    try {
      const resources = this.getUIContext().getHostContext()?.resourceManager;
      if (resources === undefined) { throw new Error('Chart UI context is unavailable'); }
      const color = resources.getColorByNameSync(this.upload ? 'dashboard_upload' : 'dashboard_download');
      const channels = `${(color >>> 16) & 255}, ${(color >>> 8) & 255}, ${color & 255}`;
      const context = this.chartContext;
      context.clearRect(0, 0, this.chartWidth, this.chartHeight);
      const points = buildTrafficChartPoints(this.history, this.chartWidth, this.chartHeight, this.upload ? 'upload' : 'download');
      if (points.length > 0) {
        const first = points[0];
        const last = points[points.length - 1];
        context.beginPath();
        context.moveTo(first.x, first.y);
        for (let index = 1; index < points.length; index++) {
          const previous = points[index - 1];
          const current = points[index];
          // 用工具函数限制后的切线构造三次贝塞尔段，避免插值制造虚假的峰值。
          const handleWidth = (current.x - previous.x) / 3;
          context.bezierCurveTo(previous.x + handleWidth, previous.y + previous.slope * handleWidth,
            current.x - handleWidth, current.y - current.slope * handleWidth, current.x, current.y);
        }
        context.strokeStyle = `rgb(${channels})`;
        context.lineWidth = 1.5;
        context.lineCap = 'round';
        context.lineJoin = 'round';
        context.stroke();
        const gradient = context.createLinearGradient(0, 0, 0, this.chartHeight);
        gradient.addColorStop(0, `rgba(${channels}, 0.32)`);
        gradient.addColorStop(1, `rgba(${channels}, 0.06)`);
        context.lineTo(last.x, this.chartHeight);
        context.lineTo(first.x, this.chartHeight);
        context.closePath();
        context.fillStyle = gradient;
        context.fill();
        if (points.length === 1) {
          context.beginPath();
          context.arc(first.x, first.y, 2, 0, Math.PI * 2);
          context.fillStyle = `rgb(${channels})`;
          context.fill();
        }
      }
      this.chartUnavailable = false;
    } catch (error) {
      if (!this.chartUnavailable) {
        hilog.warn(0x0000, 'RuntimeSpeedCard', 'Traffic chart unavailable: %{public}s', String(error));
      }
      this.chartUnavailable = true;
    }
  }

  private speed(): number {
    return (this.upload ? this.runtime?.uploadSpeed : this.runtime?.downloadSpeed) ?? 0;
  }

  private peak(): number {
    return this.history.reduce((peak: number, sample: TrafficSample): number =>
      Math.max(peak, this.upload ? sample.uploadSpeed : sample.downloadSpeed), 0);
  }

  build() {
    Column({ space: this.compact ? 4 : 8 }) {
      Row({ space: 6 }) {
        Image($r('app.media.action_arrow_up')).width(18).height(18).rotate({ angle: this.upload ? 0 : 180 })
          .fillColor(this.upload ? $r('app.color.content_secondary') : $r('app.color.dashboard_download'))
          .accessibilityLevel('no')
        Text(this.upload ? '上传' : '下载').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_secondary'))
        if (!this.compact) {
          Blank()
          Text(`峰值 ${formatSpeed(this.peak())}`).fontSize(12).fontColor($r('app.color.content_secondary'))
        }
      }
      .width('100%')
      Text() {
        Span(this.runtime === undefined ? '—' : formatBytesParts(this.speed()).value)
          .fontSize(this.compact ? 28 : 36).fontWeight(FontWeight.Bold)
        Span(this.runtime === undefined ? '' : ` ${formatBytesParts(this.speed()).unit}/s`).fontSize(12)
      }
      .fontColor($r('app.color.content_primary')).width('100%').maxLines(2)
      Text(`累计 ${this.runtime === undefined ? '—' :
        formatBytes(this.upload ? this.runtime.uploadTotal : this.runtime.downloadTotal)}`)
        .fontSize(12).fontColor($r('app.color.content_secondary')).width('100%')
      Stack({ alignContent: Alignment.BottomStart }) {
        Canvas(this.chartContext)
          .width('100%').height('100%')
          .onReady((): void => this.drawTrafficChart())
          .onAreaChange((_old: Area, area: Area): void => {
            const width = Number(area.width);
            const height = Number(area.height);
            this.chartWidth = Number.isFinite(width) ? width : 0;
            this.chartHeight = Number.isFinite(height) && height > 0 ? height : this.chartHeight;
            this.drawTrafficChart();
          })
          .accessibilityLevel('no')
          .opacity(this.proxyState !== ProxyState.ENABLED || this.chartUnavailable || !this.hasTrafficData() ? 0 : 1)
        if (this.chartUnavailable || !this.hasTrafficData() || this.proxyState !== ProxyState.ENABLED) {
          Text(this.chartUnavailable ? '曲线暂不可用' :
            (this.proxyState !== ProxyState.ENABLED ? '未连接' : '等待流量'))
            .fontSize(12).fontColor($r('app.color.content_secondary'))
        }
      }
      .width('100%').height(this.compact ? 32 : 80)
    }
    .alignItems(HorizontalAlign.Start).width(this.cardWidth)
    .constraintSize({ minHeight: this.compact ? 132 : 176 }).padding(this.compact ? 12 : 20)
    .borderRadius(this.compact ? 24 : DASHBOARD_CARD_RADIUS)
    .backgroundColor(this.compact ? $r('app.color.dashboard_inset') : $r('app.color.dashboard_surface'))
    .clip(true).accessibilityGroup(true)
    .accessibilityDescription(`最近 60 秒${this.upload ? '上传' : '下载'}速度，峰值 ${formatSpeed(this.peak())}`)
  }
}
