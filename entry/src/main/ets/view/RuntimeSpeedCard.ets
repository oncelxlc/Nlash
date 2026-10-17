import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { LengthMetrics } from '@kit.ArkUI';
import { EmptyStateBackground } from '../components/EmptyStateBackground';
import { DashboardSnapshot, TrafficSample } from '../model/RuntimeModels';
import { buildTrafficChartPoints, formatSpeed } from '../utils/RuntimeUtils';
import { CoreServiceState, ProxyState } from '../model/VpnModels';
import {
  CARD_RADIUS, CAPTION_FONT_SIZE
} from '../constants/UiConstants';

interface SpeedValueParams {
  label: string;
  speed: number | undefined;
}

@Component
export struct RuntimeSpeedCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop @Watch('onHistoryChange') history: TrafficSample[] = [];
  @Prop proxyState: ProxyState = ProxyState.DISABLED;
  @Prop coreState: CoreServiceState = CoreServiceState.STOPPED;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 176;
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
      const color = resources.getColorByNameSync('chart_line');
      const channels = `${(color >>> 16) & 255}, ${(color >>> 8) & 255}, ${color & 255}`;
      const context = this.chartContext;
      context.clearRect(0, 0, this.chartWidth, this.chartHeight);
      const points = buildTrafficChartPoints(this.history, this.chartWidth, this.chartHeight);
      if (points.length > 0) {
        const first = points[0];
        const last = points[points.length - 1];
        context.beginPath();
        context.moveTo(first.x, first.y);
        for (let index = 1; index < points.length; index++) {
          const previous = points[index - 1];
          const current = points[index];
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

  @Builder
  private speedValue($$: SpeedValueParams) {
    Text(`${$$.label} ${$$.speed === undefined ? '—' : formatSpeed($$.speed)}`)
      .fontSize(CAPTION_FONT_SIZE)
      .fontColor($r('app.color.content_secondary'))
      .maxLines(1)
      .flexShrink(0)
      .accessibilityText(`${$$.label === '↑' ? '上传' : '下载'} ${$$.speed === undefined ? '数据暂不可用' : formatSpeed($$.speed)}`)
  }

  build() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image($r('app.media.network_speed'))
          .width(16).height(16).fillColor($r('app.color.content_secondary'))
          .accessibilityLevel('no')
        Text('网络速度').fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_secondary'))
      }
      .width('100%')
      .constraintSize({ minHeight: 20 })
      Flex({
        wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start, alignItems: ItemAlign.Center,
        space: { main: LengthMetrics.vp(16), cross: LengthMetrics.vp(8) }
      }) {
        this.speedValue({ label: '↑', speed: this.runtime?.uploadSpeed })
        this.speedValue({ label: '↓', speed: this.runtime?.downloadSpeed })
      }
      .width('100%')
      Stack({ alignContent: Alignment.Center }) {
        if (this.proxyState !== ProxyState.ENABLED || this.chartUnavailable || !this.hasTrafficData()) {
          EmptyStateBackground({
            compact: true,
            title: this.proxyState !== ProxyState.ENABLED ? '未连接，统计暂停' :
              (this.chartUnavailable ? '图表暂不可用' : '等待流量')
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
          .accessibilityLevel('no')
          .opacity(this.proxyState !== ProxyState.ENABLED || this.chartUnavailable || !this.hasTrafficData() ? 0 : 1)
      }
      .width('100%')
      .height(Math.max(72, this.cardHeight - 76))
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.cardWidth)
    .constraintSize({ minHeight: this.cardHeight })
    .padding(12)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .clip(true)
    .accessibilityGroup(true)
    .accessibilityDescription('曲线展示最近 60 秒的上传与下载合计速度')
  }
}
