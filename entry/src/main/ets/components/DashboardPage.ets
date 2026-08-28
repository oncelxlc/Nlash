import { Profile, ProfileStoreSnapshot } from '../models/ProfileModels';
import {
  DashboardSnapshot,
  formatBytes,
  formatSpeed,
  LocalNetworkSnapshot,
  RuntimeMode,
  RuntimeStoreSnapshot,
  TrafficSample
} from '../models/RuntimeModels';
import { VpnState } from '../models/VpnModels';
import { feedbackService } from '../services/FeedbackService';
import { localNetworkService } from '../services/LocalNetworkService';
import { vpnService } from '../services/VpnService';
import { profileStore } from '../stores/ProfileStore';
import { runtimeStore } from '../stores/RuntimeStore';
import {
  ResponsiveMetrics,
  ResponsiveSizeClass,
  resolveDashboardSpeedCardHeight,
  resolveResponsiveMetrics
} from '../ui/ResponsiveMetrics';

const MODES: RuntimeMode[] = [RuntimeMode.RULE, RuntimeMode.GLOBAL, RuntimeMode.DIRECT];

@Component
export struct DashboardPage {
  @State vpnState: VpnState = vpnService.getState();
  @State message: string = vpnService.getLastMessage();
  @State profiles: Profile[] = [];
  @State activeProfileId: string = '';
  @State runtime: DashboardSnapshot | undefined = undefined;
  @State history: TrafficSample[] = [];
  @State localNetwork: LocalNetworkSnapshot = { localIpv4: '未知', checking: true };
  @State restarting: boolean = false;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private chartSettings: RenderingContextSettings = new RenderingContextSettings(true);
  private chartContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.chartSettings);
  private chartWidth: number = 0;
  private chartHeight: number = 320;
  private unsubscribeVpn: (() => void) | undefined = undefined;
  private unsubscribeProfiles: (() => void) | undefined = undefined;
  private unsubscribeRuntime: (() => void) | undefined = undefined;
  private unsubscribeNetwork: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribeVpn = vpnService.subscribe((state: VpnState, message: string): void => {
      this.vpnState = state;
      this.message = message;
    });
    this.unsubscribeProfiles = profileStore.subscribe((snapshot: ProfileStoreSnapshot): void => {
      this.profiles = snapshot.profiles;
      this.activeProfileId = snapshot.activeProfileId;
    });
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.runtime = snapshot.dashboard;
      this.history = snapshot.trafficHistory;
      setTimeout((): void => this.drawTrafficChart(), 0);
    });
    this.unsubscribeNetwork = localNetworkService.subscribe((snapshot: LocalNetworkSnapshot): void => {
      this.localNetwork = snapshot;
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
  }

  private getActiveProfile(): Profile | undefined {
    return this.profiles.find((profile: Profile): boolean => profile.id === this.activeProfileId);
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
    try {
      await runtimeStore.setMode(mode);
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
      Row() {
        Column({ space: 5 }) {
          this.cardTitle('VPN 代理')
          Text(this.message.length > 0 ? this.message : '整机 VPN / TUN')
            .fontSize(12)
            .fontColor($r('app.color.content_secondary'))
            .maxLines(2)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.isVpnActive() })
          .enabled(!this.isVpnBusy() && (this.isVpnActive() || this.getActiveProfile() !== undefined))
          .onChange((enabled: boolean): void => { this.toggleVpn(enabled); })
      }
      .width('100%')
      Row({ space: 8 }) {
        ForEach(MODES, (mode: RuntimeMode) => {
          Button(this.modeLabel(mode))
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .height(32)
            .fontSize(13)
            .fontColor(this.runtime?.mode === mode ? Color.White : $r('app.color.content_primary'))
            .backgroundColor(this.runtime?.mode === mode ?
              $r('app.color.nav_selected') : $r('app.color.app_background'))
            .enabled(this.vpnState === VpnState.CONNECTED)
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
  private dashboardCards() {
    if (this.metrics.sizeClass === ResponsiveSizeClass.COMPACT) {
      Column({ space: this.metrics.cardGap }) {
        this.speedCard('100%')
        this.trafficCard('100%')
        this.vpnCard('100%')
        this.infoCard('运行状态', `${this.runtime?.connectionCount ?? 0} 个活动连接`,
          `Core 内存 ${formatBytes(this.runtime?.memoryBytes ?? 0)}`, '100%')
        this.infoCard('本机网络', this.localNetwork.localIpv4,
          this.localNetwork.checking ? '正在检测本机网络…' :
            (this.localNetwork.localIpv4 === '未知' ? '未检测到可用 IPv4 地址' : '已自动检测本机 IPv4'), '100%')
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
          this.infoCard('本机网络', this.localNetwork.localIpv4,
            this.localNetwork.checking ? '正在检测本机网络…' :
              (this.localNetwork.localIpv4 === '未知' ? '未检测到可用 IPv4 地址' : '已自动检测本机 IPv4'),
            this.metrics.dashboardCardWidth)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
    }
  }

  build() {
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
      .padding(this.metrics.pagePadding)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_oldValue: Area, newValue: Area): void => { this.updateWidth(newValue.width); })
  }
}
