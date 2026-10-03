import { RuntimeStatusCard } from './RuntimeStatusCard';
import { RuntimeTrafficCard } from './RuntimeTrafficCard';
import { RuntimeSpeedCard } from './RuntimeSpeedCard';
import { Profile } from '../model/ProfileModels';
import { DashboardSnapshot, PublicNetworkSnapshot, RuntimeMode, TrafficSample } from '../model/RuntimeModels';
import { DEFAULT_RUNTIME_MODE } from '../constants/RuntimeConstants';
import { CoreServiceState, ProxyState } from '../model/VpnModels';
import { formatVpnRunDuration } from '../utils/VpnUtils';
import { feedbackService } from '../services/FeedbackService';
import { publicNetworkService } from '../services/LocalNetworkService';
import { vpnService } from '../services/VpnService';
import { profileStore } from '../stores/ProfileStore';
import { runtimeStore } from '../stores/RuntimeStore';
import { ResponsiveMetrics, ResponsiveSizeClass } from '../model/ResponsiveModels';
import {
  resolveResponsiveMetrics,
  resolveContentWidth
} from '../utils/ResponsiveUtils';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE
} from '../constants/UiConstants';
import { PageHeader } from '../components/PageHeader';
import { AppPage } from '../model/NavigationModels';
import { navigationIntentService } from '../services/NavigationIntentService';

const MODES: RuntimeMode[] = [RuntimeMode.RULE, RuntimeMode.GLOBAL, RuntimeMode.DIRECT];
const VIEW_SYNC_INTERVAL_MS = 1000;

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
  @State publicNetworkChecking: boolean = true;
  @State publicNetworkError: string = '';
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
    this.publicNetworkChecking = snapshot.checking;
    this.publicNetworkError = snapshot.errorMessage;
  }

  private getActiveProfile(): Profile | undefined {
    return this.profiles.find((profile: Profile): boolean => profile.id === this.activeProfileId);
  }

  private publicNetworkDetail(): string {
    const location = this.publicCountry;
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
    this.metrics = resolveResponsiveMetrics(resolveContentWidth(width));
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


  private proxyStatus(): string {
    switch (this.proxyState) {
      case ProxyState.ENABLED: return '代理已连接';
      case ProxyState.ENABLING: return '正在连接…';
      case ProxyState.DISABLING: return '正在断开…';
      case ProxyState.ERROR: return '连接异常';
      default: return '代理未连接';
    }
  }

  @Builder
  private headerActions() {
    Button({ type: ButtonType.Normal }) {
      Image($r('app.media.action_more'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.content_primary'))
    }
    .width(CONTROL_HEIGHT)
    .height(CONTROL_HEIGHT)
    .borderRadius(BUTTON_RADIUS)
    .backgroundColor($r('app.color.surface_muted'))
    .accessibilityText('Core 操作')
    .bindMenu([{
      value: this.restarting ? '正在重启 Core…' : '重启 Core',
      enabled: !this.restarting && this.coreState !== CoreServiceState.STARTING &&
        this.coreState !== CoreServiceState.RELOADING,
      action: (): void => { this.confirmCoreRestart(); }
    }])
  }

  @Builder
  private controlPanel() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 6 }) {
            Text(this.connectedAt > 0 ? `已连接 · ${formatVpnRunDuration(this.elapsedSeconds)}` : this.proxyStatus())
              .fontSize(CAPTION_FONT_SIZE)
              .fontColor(this.proxyState === ProxyState.ERROR ? $r('app.color.status_error') :
                (this.proxyState === ProxyState.ENABLED ? $r('app.color.nav_selected') : $r('app.color.content_secondary')))
              .width('100%')
            Text(this.getActiveProfile()?.name ?? '添加配置')
              .fontSize(BODY_FONT_SIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.content_primary'))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: CONTROL_HEIGHT })
        .padding(0)
        .borderRadius(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(`当前配置：${this.getActiveProfile()?.name ?? '未选择'}，打开配置页`)
        .onClick((): void => { navigationIntentService.publish(AppPage.CONFIGURATION); })
        Select([{ value: '规则模式' }, { value: '全局模式' }, { value: '直连模式' }])
          .selected(MODES.indexOf(this.selectedMode))
          .value(this.modeLabel(this.selectedMode))
          .font({ size: 14, weight: FontWeight.Medium })
          .fontColor($r('app.color.nav_selected'))
          .backgroundColor($r('app.color.nav_selected_background'))
          .constraintSize({ minWidth: 84 })
          .height(CONTROL_HEIGHT)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.coreState === CoreServiceState.RUNNING && this.runtimeBusyKey.length === 0)
          .accessibilityText(`流量处理模式：${this.modeLabel(this.selectedMode)}`)
          .onSelect((index: number): void => {
            const mode = MODES[index];
            if (mode !== undefined) { this.setMode(mode); }
          })
        Button(this.isProxyBusy() ? '处理中' : (this.isProxyActive() ? '断开' : '连接'))
          .type(ButtonType.Normal)
          .height(CONTROL_HEIGHT)
          .constraintSize({ minWidth: 72 })
          .padding({ left: 8, right: 8 })
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .borderRadius(BUTTON_RADIUS)
          .fontColor(this.isProxyActive() ? $r('app.color.nav_selected') : $r('app.color.accent_foreground'))
          .backgroundColor(this.isProxyActive() ? $r('app.color.nav_selected_background') : $r('app.color.nav_selected'))
          .enabled(!this.isProxyBusy() && (this.isProxyActive() ||
            (this.coreState === CoreServiceState.RUNNING && this.getActiveProfile() !== undefined)))
          .accessibilityText(this.isProxyActive() ? '断开 VPN 代理' : '连接 VPN 代理')
          .onClick((): void => { this.toggleProxy(!this.isProxyActive()); })
      }
      .width('100%')
      if (this.coreState === CoreServiceState.ERROR || this.proxyState === ProxyState.ERROR) {
        Text(this.message || '连接遇到问题，请检查配置后重试。')
          .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.status_error')).width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private publicNetworkCard() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text('公网出口')
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary'))
        Text(this.publicIpv4 === '未知' ? '—' : this.publicIpv4)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
          .wordBreak(WordBreak.BREAK_ALL)
        Text(this.publicNetworkDetail())
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor(this.publicNetworkError.length > 0 ? $r('app.color.status_error') : $r('app.color.content_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Button({ type: ButtonType.Normal }) {
        if (this.publicNetworkChecking) {
          LoadingProgress().width(20).height(20).color($r('app.color.nav_selected'))
        } else {
          Image($r('app.media.action_refresh'))
            .width(20).height(20).fillColor($r('app.color.nav_selected'))
        }
      }
      .width(CONTROL_HEIGHT)
      .height(CONTROL_HEIGHT)
      .borderRadius(BUTTON_RADIUS)
      .backgroundColor($r('app.color.surface_muted'))
      .enabled(!this.publicNetworkChecking)
      .accessibilityText('刷新公网出口')
      .onClick((): void => { publicNetworkService.refresh(); })
    }
    .width('100%')
    .padding(16)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private runtimeSummary() {
    Column({ space: 12 }) {
      RuntimeTrafficCard({ runtime: this.runtime })
      RuntimeStatusCard({ runtime: this.runtime })
      this.publicNetworkCard()
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: this.metrics.sectionGap }) {
        PageHeader({
          title: $r('app.string.nav_dashboard'), subtitle: this.coreStatus(),
          actions: (): void => { this.headerActions(); }
        })
        this.controlPanel()
        if (this.metrics.sizeClass === ResponsiveSizeClass.COMPACT) {
          RuntimeSpeedCard({
            runtime: this.runtime, history: this.history,
            proxyState: this.proxyState, coreState: this.coreState
          })
          this.runtimeSummary()
        } else {
          Row({ space: this.metrics.cardGap }) {
            Column() {
              RuntimeSpeedCard({
                runtime: this.runtime, history: this.history,
                proxyState: this.proxyState, coreState: this.coreState,
                cardHeight: 320
              })
            }
            .layoutWeight(3)
            Column() { this.runtimeSummary() }
              .layoutWeight(2)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .justifyContent(FlexAlign.Start)
      .padding({
        top: this.metrics.pagePadding, left: this.metrics.pagePadding, right: this.metrics.pagePadding,
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_old: Area, area: Area): void => { this.updateWidth(area.width); })
  }
}
