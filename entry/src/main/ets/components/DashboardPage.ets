import { Profile, ProfileStoreSnapshot } from '../models/ProfileModels';
import {
  DashboardSnapshot,
  DEFAULT_RUNTIME_MODE,
  formatBytes,
  formatSpeed,
  PublicNetworkSnapshot,
  RuntimeMode,
  RuntimeStoreSnapshot,
  TrafficSample
} from '../models/RuntimeModels';
import { formatVpnRunDuration, VpnState } from '../models/VpnModels';
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

@Component
export struct DashboardPage {
  @State vpnState: VpnState = vpnService.getState();
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
  @State restarting: boolean = false;
  @State selectedMode: RuntimeMode = DEFAULT_RUNTIME_MODE;
  @State runtimeBusyKey: string = '';
  @State elapsedSeconds: number = 0;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private chartSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private chartContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.chartSettings);
  private chartWidth: number = 0;
  private chartHeight: number = 320;
  private unsubscribeVpn: (() => void) | undefined = undefined;
  private unsubscribeProfiles: (() => void) | undefined = undefined;
  private unsubscribeRuntime: (() => void) | undefined = undefined;
  private unsubscribeNetwork: (() => void) | undefined = undefined;
  private elapsedTimer: number | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribeVpn = vpnService.subscribe((state: VpnState, message: string): void => {
      this.vpnState = state;
      this.message = message;
      if (this.unsubscribeNetwork !== undefined &&
        (state === VpnState.CONNECTED || state === VpnState.DISCONNECTED || state === VpnState.ERROR)) {
        publicNetworkService.refresh();
      }
      if (state === VpnState.IDLE || state === VpnState.DISCONNECTED || state === VpnState.ERROR) {
        this.selectedMode = DEFAULT_RUNTIME_MODE;
      }
      this.syncElapsedTimer();
    });
    this.unsubscribeProfiles = profileStore.subscribe((snapshot: ProfileStoreSnapshot): void => {
      this.profiles = snapshot.profiles;
      this.activeProfileId = snapshot.activeProfileId;
    });
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.runtime = snapshot.dashboard;
      this.history = snapshot.trafficHistory;
      this.runtimeBusyKey = snapshot.busyKey;
      if (snapshot.dashboard !== undefined) {
        this.selectedMode = snapshot.dashboard.mode;
      }
      setTimeout((): void => this.drawTrafficChart(), 0);
    });
    this.unsubscribeNetwork = publicNetworkService.subscribe((snapshot: PublicNetworkSnapshot): void => {
      this.publicIpv4 = snapshot.publicIpv4;
      this.publicCountry = snapshot.country;
      this.publicCountryCode = snapshot.countryCode;
      this.publicNetworkChecking = snapshot.checking;
      this.publicNetworkError = snapshot.errorMessage;
    });
  }

  aboutToDisappear(): void {
    this.unsubscribeVpn?.();
    this.unsubscribeProfiles?.();
    this.unsubscribeRuntime?.();
    this.unsubscribeNetwork?.();
    this.unsubscribeVpn = undefined;
    this.unsubscribeProfiles = undefined;
    this.unsubscribeRuntime = undefined;
    this.unsubscribeNetwork = undefined;
    this.stopElapsedTimer();
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

  private isVpnBusy(): boolean {
    return this.vpnState === VpnState.REQUESTING_PERMISSION || this.vpnState === VpnState.STARTING ||
      this.vpnState === VpnState.STOPPING;
  }

  private isVpnActive(): boolean {
    return this.vpnState === VpnState.CONNECTED || this.isVpnBusy();
  }

  private async toggleVpn(enabled: boolean): Promise<void> {
    try {
      if (!enabled) {
        await vpnService.stop();
      } else if (this.getActiveProfile() === undefined) {
        feedbackService.warning('请先添加并选择一份配置');
      } else {
        await vpnService.start();
      }
    } catch (error) {
    }
  }

  private coreStatus(): string {
    if (this.vpnState === VpnState.CONNECTED) {
      return 'Core 运行中';
    }
    if (this.isVpnBusy()) {
      return 'Core 切换中';
    }
    if (this.vpnState === VpnState.ERROR) {
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
    if (this.isVpnBusy() || this.restarting) {
      return;
    }
    if (this.getActiveProfile() === undefined) {
      feedbackService.warning('请先添加并选择一份配置');
      return;
    }
    const stopped = this.vpnState === VpnState.IDLE || this.vpnState === VpnState.DISCONNECTED;
    AlertDialog.show({
      title: stopped ? '启动 Core' : '重启 Core',
      message: stopped ? '确定使用当前配置启动 Core 吗？' : '确定停止当前连接并重新启动 Core 吗？',
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: stopped ? '启动' : '重启',
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
    } finally {
      this.restarting = false;
    }
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : '操作失败';
  }

  private syncElapsedTimer(): void {
    this.updateElapsedSeconds();
    if (vpnService.getConnectedAt() > 0) {
      if (this.elapsedTimer === undefined) {
        this.elapsedTimer = setInterval((): void => this.updateElapsedSeconds(), 1000);
      }
    } else {
      this.stopElapsedTimer();
    }
  }

  private updateElapsedSeconds(): void {
    const connectedAt = vpnService.getConnectedAt();
    this.elapsedSeconds = connectedAt > 0 ? Math.max(0, Math.floor((Date.now() - connectedAt) / 1000)) : 0;
  }

  private stopElapsedTimer(): void {
    if (this.elapsedTimer !== undefined) {
      clearInterval(this.elapsedTimer);
      this.elapsedTimer = undefined;
    }
  }

  private hasRunStarted(): boolean {
    return vpnService.getConnectedAt() > 0;
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
    this.history.forEach((sample: TrafficSample, index: number): void => {
      const x = this.history.length === 1 ? 0 : index * this.chartWidth / (this.history.length - 1);
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

  @Builder
  private cardTitle(title: string) {
    Text(title)
      .fontSize(14)
      .fontWeight(FontWeight.Medium)
      .fontColor($r('app.color.content_primary'))
      .width('100%')
  }

  @Builder
  private speedCard(cardWidth: Length) {
    Column({ space: 10 }) {
      Row() {
        this.cardTitle('网络速度 · 最近 60 秒')
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
            Text(this.vpnState === VpnState.CONNECTED ? '正在等待网络流量' : '连接 VPN 后显示实时曲线')
              .fontSize(12)
              .fontColor($r('app.color.content_secondary'))
          }
        }
      }
        .width('100%')
        .layoutWeight(1)
    }
    .alignItems(HorizontalAlign.Start)
    .width(cardWidth)
    .height(resolveDashboardSpeedCardHeight(this.metrics))
    .padding(14)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private trafficCard(cardWidth: Length) {
    Column({ space: 8 }) {
      this.cardTitle('累计流量')
      Row({ space: 14 }) {
        DataPanel({
          values: [this.runtime?.uploadTotal ?? 0, this.runtime?.downloadTotal ?? 0],
          max: Math.max(1, (this.runtime?.uploadTotal ?? 0) + (this.runtime?.downloadTotal ?? 0)),
          type: DataPanelType.Circle
        })
          .width(56)
          .height(56)
        Column({ space: 7 }) {
          Text(`↑  ${formatBytes(this.runtime?.uploadTotal ?? 0)}`)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary'))
          Text(`↓  ${formatBytes(this.runtime?.downloadTotal ?? 0)}`)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary'))
        }
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)
    }
    .alignItems(HorizontalAlign.Start)
    .width(cardWidth)
    .height(this.metrics.dashboardCardHeight)
    .padding(12)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private vpnCard(cardWidth: Length) {
    Column({ space: 8 }) {
      this.cardTitle('VPN 代理模式')
      Text(this.vpnState === VpnState.CONNECTED ? '选择 Core 当前的流量处理方式' : '连接 VPN 后可切换模式')
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
            .enabled(this.vpnState === VpnState.CONNECTED && this.runtimeBusyKey.length === 0)
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
        Text(this.hasRunStarted() ? 'Ⅱ' : '▶')
          .fontSize(this.hasRunStarted() ? 19 : 17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.vpn_fab_foreground'))
        if (this.hasRunStarted()) {
          Text(formatVpnRunDuration(this.elapsedSeconds))
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.vpn_fab_foreground'))
        }
      }
      .justifyContent(FlexAlign.Center)
    }
    .width(this.hasRunStarted() ? 126 : 56)
    .height(56)
    .borderRadius(BUTTON_RADIUS)
    .backgroundColor($r('app.color.vpn_fab_background'))
    .enabled(!this.isVpnBusy() && (this.isVpnActive() || this.getActiveProfile() !== undefined))
    .accessibilityText(this.hasRunStarted() ? '停止 VPN' : '启动 VPN')
    .margin({ right: this.metrics.pagePadding, bottom: this.metrics.pagePadding })
    .zIndex(2)
    .onClick((): void => { this.toggleVpn(!this.isVpnActive()); })
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
  }

  @Builder
  private dashboardCards() {
    if (this.metrics.sizeClass === ResponsiveSizeClass.COMPACT) {
      Column({ space: this.metrics.cardGap }) {
        this.speedCard('100%')
        this.trafficCard('100%')
        this.vpnCard('100%')
        this.infoCard('运行状态', `${this.runtime?.connectionCount ?? 0} 个活动连接`,
          `Core 内存 ${formatBytes(this.runtime?.memoryBytes ?? 0)}`, '100%')
        this.publicNetworkCard('100%')
      }
      .width('100%')
    } else {
      Column({ space: this.metrics.cardGap }) {
        Row() {
          this.speedCard(this.metrics.dashboardCardWidth)
          Column({ space: this.metrics.cardGap }) {
            this.trafficCard('100%')
            this.vpnCard('100%')
          }
          .width(this.metrics.dashboardCardWidth)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .alignItems(VerticalAlign.Top)
        Row() {
          this.infoCard('运行状态', `${this.runtime?.connectionCount ?? 0} 个活动连接`,
            `Core 内存 ${formatBytes(this.runtime?.memoryBytes ?? 0)}`, this.metrics.dashboardCardWidth)
          this.publicNetworkCard(this.metrics.dashboardCardWidth)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
    }
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
              .fontColor(this.vpnState === VpnState.CONNECTED ?
                $r('app.color.status_success') : $r('app.color.content_secondary'))
              .enabled(!this.isVpnBusy() && !this.restarting)
              .opacity(this.isVpnBusy() || this.restarting ? 0.55 : 1)
              .onClick((): void => { this.confirmCoreRestart(); })
          }
          .width('100%')

          this.dashboardCards()
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
