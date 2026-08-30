import { Profile } from '../models/ProfileModels';
import {
  DashboardSnapshot,
  DEFAULT_RUNTIME_MODE,
  formatBytes,
  formatBytesParts,
  formatSpeed,
  PublicNetworkSnapshot,
  RuntimeMode,
  TrafficSample
} from '../models/RuntimeModels';
import {
  CoreServiceState,
  formatVpnRunDuration,
  ProxyState
} from '../models/VpnModels';
import { feedbackService } from '../services/FeedbackService';
import { countryCodeFlag, publicNetworkService } from '../services/LocalNetworkService';
import { vpnService } from '../services/VpnService';
import { profileStore } from '../stores/ProfileStore';
import { runtimeStore } from '../stores/RuntimeStore';
import {
  ResponsiveMetrics,
  ResponsiveSizeClass,
  resolveDashboardSpeedCardHeight,
  resolveResponsiveMetrics
} from '../ui/ResponsiveMetrics';
import { BUTTON_RADIUS } from '../ui/UiConstants';

const MODES: RuntimeMode[] = [RuntimeMode.RULE, RuntimeMode.GLOBAL, RuntimeMode.DIRECT];
const VIEW_SYNC_INTERVAL_MS = 1000;

@Component
struct RuntimeSpeedCard {
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

@Component
struct RuntimeTrafficCard {
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

@Component
struct RuntimeStatusCard {
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardWidth: Length = '100%';
  @Prop cardHeight: number = 120;

  build() {
    Column({ space: 6 }) {
      Text('运行状态')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .width('100%')
      Text(`${this.runtime?.connectionCount ?? 0} 个活动连接`)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .maxLines(1)
      Text(`Core 内存 ${formatBytes(this.runtime?.memoryBytes ?? 0)}`)
        .fontSize(12)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(2)
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width(this.cardWidth)
    .height(this.cardHeight)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }
}

@Component
export struct DashboardPage {
  @State coreState: CoreServiceState = vpnService.getCoreState();
  @State proxyState: ProxyState = vpnService.getProxyState();
  @State message: string = vpnService.getLastMessage();
  @State profiles: Profile[] = [];
  @State activeProfileId: string = '';
  @State runtime: DashboardSnapshot | undefined = undefined;
  @State history: TrafficSample[] = [];
  @State publicIpv4: string = '未知';
  @State publicCountry: string = '未知地区';
  @State publicCountryCode: string = '';
  @State publicNetworkChecking: boolean = true;
  @State publicNetworkError: string = '';
  @State publicNetworkCardPressed: boolean = false;
  @State restarting: boolean = false;
  @State selectedMode: RuntimeMode = DEFAULT_RUNTIME_MODE;
  @State runtimeBusyKey: string = '';
  @State connectedAt: number = vpnService.getConnectedAt();
  @State elapsedSeconds: number = 0;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribeNetwork: (() => void) | undefined = undefined;
  private viewSyncTimer: number | undefined = undefined;
  private lastTrafficSampleTimestamp: number = 0;

  aboutToAppear(): void {
    this.unsubscribeNetwork = publicNetworkService.subscribe((snapshot: PublicNetworkSnapshot): void => {
      this.applyPublicNetworkSnapshot(snapshot);
    });
    this.syncViewState();
    this.viewSyncTimer = setInterval((): void => this.syncViewState(), VIEW_SYNC_INTERVAL_MS);
    runtimeStore.refresh();
  }

  aboutToDisappear(): void {
    this.unsubscribeNetwork?.();
    this.unsubscribeNetwork = undefined;
    if (this.viewSyncTimer !== undefined) {
      clearInterval(this.viewSyncTimer);
      this.viewSyncTimer = undefined;
    }
  }

  private syncViewState(): void {
    const lifecycle = vpnService.getLifecycleSnapshot();
    this.coreState = lifecycle.coreState;
    this.proxyState = lifecycle.proxyState;
    this.message = lifecycle.message;
    this.connectedAt = vpnService.getConnectedAt();
    const profileSnapshot = profileStore.getSnapshot();
    this.profiles = profileSnapshot.profiles;
    this.activeProfileId = profileSnapshot.activeProfileId;

    const runtimeSnapshot = runtimeStore.getSnapshot();
    this.runtime = runtimeSnapshot.dashboard;
    this.runtimeBusyKey = runtimeSnapshot.busyKey;
    if (runtimeSnapshot.dashboard !== undefined) {
      this.selectedMode = runtimeSnapshot.dashboard.mode;
    } else if (lifecycle.coreState === CoreServiceState.WAITING_CONFIG ||
      lifecycle.coreState === CoreServiceState.STOPPED || lifecycle.coreState === CoreServiceState.ERROR) {
      this.selectedMode = DEFAULT_RUNTIME_MODE;
    }
    const latestSampleTimestamp = runtimeSnapshot.trafficHistory.length > 0 ?
      runtimeSnapshot.trafficHistory[runtimeSnapshot.trafficHistory.length - 1].timestamp : 0;
    if (latestSampleTimestamp !== this.lastTrafficSampleTimestamp) {
      this.lastTrafficSampleTimestamp = latestSampleTimestamp;
      this.history = runtimeSnapshot.trafficHistory;
    }

    this.applyPublicNetworkSnapshot(publicNetworkService.getSnapshot());
    this.updateElapsedSeconds();
  }

  private applyPublicNetworkSnapshot(snapshot: PublicNetworkSnapshot): void {
    this.publicIpv4 = snapshot.publicIpv4;
    this.publicCountry = snapshot.country;
    this.publicCountryCode = snapshot.countryCode;
    this.publicNetworkChecking = snapshot.checking;
    this.publicNetworkError = snapshot.errorMessage;
  }

  private getActiveProfile(): Profile | undefined {
    return this.profiles.find((profile: Profile): boolean => profile.id === this.activeProfileId);
  }

  private publicNetworkDetail(): string {
    const location = `${countryCodeFlag(this.publicCountryCode)} ${this.publicCountry}`;
    if (this.publicNetworkChecking) {
      return this.publicIpv4 === '未知' ? '正在查询公网 IPv4…' : `${location} · 正在刷新`;
    }
    if (this.publicNetworkError.length > 0) {
      return this.publicIpv4 === '未知' ? this.publicNetworkError :
        `${location} · 刷新失败`;
    }
    return location;
  }

  private updateWidth(width: Length): void {
    const numericWidth = typeof width === 'number' ? width : (typeof width === 'string' ? Number(width) : 0);
    this.metrics = resolveResponsiveMetrics(Number.isFinite(numericWidth) ? numericWidth : 0);
  }

  private isProxyBusy(): boolean {
    return this.proxyState === ProxyState.ENABLING || this.proxyState === ProxyState.DISABLING;
  }

  private isProxyActive(): boolean {
    return this.proxyState === ProxyState.ENABLED || this.proxyState === ProxyState.ENABLING;
  }

  private async toggleProxy(enabled: boolean): Promise<void> {
    try {
      if (!enabled) {
        await vpnService.stop();
      } else if (this.getActiveProfile() === undefined) {
        feedbackService.warning('请先添加并选择一份配置');
      } else {
        await vpnService.start();
      }
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private coreStatus(): string {
    if (this.coreState === CoreServiceState.RUNNING) {
      return 'Core 运行中';
    }
    if (this.coreState === CoreServiceState.STARTING) {
      return 'Core 启动中';
    }
    if (this.coreState === CoreServiceState.RELOADING) {
      return 'Core 重载中';
    }
    if (this.coreState === CoreServiceState.WAITING_CONFIG) {
      return '等待活动配置';
    }
    if (this.coreState === CoreServiceState.ERROR) {
      return 'Core 异常';
    }
    return 'Core 已停止';
  }

  private modeLabel(mode: RuntimeMode): string {
    if (mode === RuntimeMode.GLOBAL) {
      return '全局';
    }
    if (mode === RuntimeMode.DIRECT) {
      return '直连';
    }
    return '规则';
  }

  private async setMode(mode: RuntimeMode): Promise<void> {
    if (mode === this.selectedMode || this.runtimeBusyKey.length > 0) {
      return;
    }
    try {
      await runtimeStore.setMode(mode);
      this.selectedMode = mode;
      feedbackService.success(`已切换为${this.modeLabel(mode)}模式`);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private confirmCoreRestart(): void {
    if (this.coreState === CoreServiceState.STARTING || this.coreState === CoreServiceState.RELOADING ||
      this.restarting) {
      return;
    }
    if (this.getActiveProfile() === undefined) {
      feedbackService.warning('请先添加并选择一份配置');
      return;
    }
    AlertDialog.show({
      title: '重启 Core',
      message: '确定重新加载当前配置吗？如代理已开启，完成后会自动重建 VPN。',
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '重启',
        action: (): void => {
          this.restartCore();
        }
      }
    });
  }

  private async restartCore(): Promise<void> {
    this.restarting = true;
    try {
      await vpnService.restart();
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    } finally {
      this.restarting = false;
    }
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : '操作失败';
  }

  private updateElapsedSeconds(): void {
    this.elapsedSeconds = this.connectedAt > 0 ?
      Math.max(0, Math.floor((Date.now() - this.connectedAt) / 1000)) : 0;
  }

  private hasRunStarted(): boolean {
    return this.connectedAt > 0;
  }

  @Builder
  private cardTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.content_primary'))
      .width('100%')
  }

  @Builder
  private vpnCard(cardWidth: Length) {
    Column({ space: 8 }) {
      this.cardTitle('VPN 代理模式')
      Text(this.coreState === CoreServiceState.RUNNING ?
        '选择 Core 的流量处理方式，代理开启时生效' : 'Core 就绪后可切换模式')
        .fontSize(12)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(1)
        .width('100%')
      Row({ space: 8 }) {
        ForEach(MODES, (mode: RuntimeMode) => {
          Button(this.modeLabel(mode))
            .type(ButtonType.Normal)
            .borderRadius(BUTTON_RADIUS)
            .layoutWeight(1)
            .height(32)
            .fontSize(13)
            .fontColor(mode === RuntimeMode.RULE ? $r('app.color.mode_rule_foreground') :
              (mode === RuntimeMode.GLOBAL ? $r('app.color.mode_global_foreground') :
                $r('app.color.mode_direct_foreground')))
            .backgroundColor(this.selectedMode !== mode ? $r('app.color.mode_unselected_background') :
              (mode === RuntimeMode.RULE ? $r('app.color.mode_rule_background') :
                (mode === RuntimeMode.GLOBAL ? $r('app.color.mode_global_background') :
                  $r('app.color.mode_direct_background'))))
            .enabled(this.coreState === CoreServiceState.RUNNING && this.runtimeBusyKey.length === 0)
            .onClick((): void => { this.setMode(mode); })
        }, (mode: RuntimeMode): string => mode)
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width(cardWidth)
    .height(this.metrics.dashboardCardHeight)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private floatingVpnButton() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        if (this.hasRunStarted()) {
          Image($r('app.media.ic_public_pause'))
            .width(20)
            .height(20)
            .colorFilter($r('app.color.vpn_fab_foreground'))
          Text(formatVpnRunDuration(this.elapsedSeconds))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.vpn_fab_foreground'))
        } else {
          Image($r('app.media.ic_public_play'))
            .width(20)
            .height(20)
            .colorFilter($r('app.color.vpn_fab_foreground'))
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(this.hasRunStarted() ? 126 : 56)
    .height(56)
    .borderRadius(BUTTON_RADIUS)
    .backgroundColor($r('app.color.vpn_fab_background'))
    .enabled(!this.isProxyBusy() &&
      (this.isProxyActive() || (this.coreState === CoreServiceState.RUNNING &&
        this.getActiveProfile() !== undefined)))
    .accessibilityText(this.hasRunStarted() ? '关闭代理' : '开启代理')
    .margin({ right: this.metrics.pagePadding, bottom: this.metrics.pagePadding })
    .zIndex(2)
    .onClick((): void => { this.toggleProxy(!this.isProxyActive()); })
  }

  @Builder
  private infoCard(title: string, value: string, detail: string, cardWidth: Length) {
    Column({ space: 5 }) {
      this.cardTitle(title)
      Text(value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.content_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(detail)
        .fontSize(12)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(2)
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width(cardWidth)
    .height(this.metrics.dashboardInfoCardHeight)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private publicNetworkCard(cardWidth: Length) {
    Column({ space: 5 }) {
      this.cardTitle('公网出口')
      Text(this.publicIpv4)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.content_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.publicNetworkDetail())
        .fontSize(12)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(2)
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width(cardWidth)
    .height(this.metrics.dashboardInfoCardHeight)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .scale({ x: this.publicNetworkCardPressed ? 0.98 : 1, y: this.publicNetworkCardPressed ? 0.98 : 1 })
    .opacity(this.publicNetworkCardPressed ? 0.86 : 1)
    .animation({ duration: 120, curve: Curve.EaseOut })
    .accessibilityText('刷新公网出口')
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.publicNetworkCardPressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.publicNetworkCardPressed = false;
      }
    })
    .onClick((): void => {
      publicNetworkService.refresh();
    })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll() {
        Column({ space: this.metrics.sectionGap }) {
          Row({ space: 12 }) {
            Column({ space: 4 }) {
              Text($r('app.string.nav_dashboard'))
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.content_primary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(this.coreStatus())
              .fontSize(12)
              .fontColor(this.coreState === CoreServiceState.RUNNING ?
                $r('app.color.status_success') : $r('app.color.content_secondary'))
              .enabled(this.coreState !== CoreServiceState.STARTING &&
                this.coreState !== CoreServiceState.RELOADING && !this.restarting)
              .opacity(this.coreState === CoreServiceState.STARTING ||
                this.coreState === CoreServiceState.RELOADING || this.restarting ? 0.55 : 1)
              .onClick((): void => { this.confirmCoreRestart(); })
          }
          .width('100%')

          if (this.metrics.sizeClass === ResponsiveSizeClass.COMPACT) {
            Column({ space: this.metrics.cardGap }) {
              RuntimeSpeedCard({
                runtime: this.runtime,
                history: this.history,
                proxyState: this.proxyState,
                coreState: this.coreState,
                cardWidth: '100%',
                cardHeight: resolveDashboardSpeedCardHeight(this.metrics)
              })
              RuntimeTrafficCard({
                runtime: this.runtime,
                cardWidth: '100%',
                cardHeight: this.metrics.dashboardCardHeight
              })
              this.vpnCard('100%')
              RuntimeStatusCard({
                runtime: this.runtime,
                cardWidth: '100%',
                cardHeight: this.metrics.dashboardInfoCardHeight
              })
              this.publicNetworkCard('100%')
            }
            .width('100%')
          } else {
            Column({ space: this.metrics.cardGap }) {
              Row() {
                RuntimeSpeedCard({
                  runtime: this.runtime,
                  history: this.history,
                  proxyState: this.proxyState,
                  coreState: this.coreState,
                  cardWidth: this.metrics.dashboardCardWidth,
                  cardHeight: resolveDashboardSpeedCardHeight(this.metrics)
                })
                Column({ space: this.metrics.cardGap }) {
                  RuntimeTrafficCard({
                    runtime: this.runtime,
                    cardWidth: '100%',
                    cardHeight: this.metrics.dashboardCardHeight
                  })
                  this.vpnCard('100%')
                }
                .width(this.metrics.dashboardCardWidth)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
              .alignItems(VerticalAlign.Top)
              Row() {
                RuntimeStatusCard({
                  runtime: this.runtime,
                  cardWidth: this.metrics.dashboardCardWidth,
                  cardHeight: this.metrics.dashboardInfoCardHeight
                })
                this.publicNetworkCard(this.metrics.dashboardCardWidth)
              }
              .width('100%')
              .justifyContent(FlexAlign.SpaceBetween)
            }
            .width('100%')
          }
        }
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({
          top: this.metrics.pagePadding,
          left: this.metrics.pagePadding,
          right: this.metrics.pagePadding,
          bottom: this.metrics.pagePadding + 80
        })
      }
      .width('100%')
      .height('100%')

      this.floatingVpnButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_oldValue: Area, newValue: Area): void => { this.updateWidth(newValue.width); })
  }
}
