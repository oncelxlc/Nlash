import { AppTheme } from '../model/ThemeModels';
import { ThemeAlertDialog } from '../components/ThemeAlertDialog';
import { themeMenu } from '../components/ThemeMenu';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { RuntimeStatusCard } from './RuntimeStatusCard';
import { RuntimeSpeedCard } from './RuntimeSpeedCard';
import { RuntimeMemoryCard } from './RuntimeMemoryCard';
import { SubscriptionUsageBar } from '../components/SubscriptionUsageBar';
import { LengthMetrics } from '@kit.ArkUI';
import { systemDateTime } from '@kit.BasicServicesKit';
import { Profile, ProfileStoreSnapshot, ProfileType } from '../model/ProfileModels';
import { DashboardSnapshot, IpNetworkType, IpQuality, PublicNetworkSnapshot, RuntimeMode,
  TrafficSample, ProxyGroupSnapshot } from '../model/RuntimeModels';
import { DEFAULT_RUNTIME_MODE } from '../constants/RuntimeConstants';
import { CoreServiceState, ProxyState, RuntimeLifecycleSnapshot } from '../model/VpnModels';
import { proxySessionElapsedSeconds, formatVpnRunDuration } from '../utils/VpnUtils';
import { profileUsageRatio, formatProfileBytes, formatProfileRemainingDays, formatProfileRelativeTime } from '../utils/ProfileUtils';
import { DashboardCard } from '../model/DashboardModels';
import {
  dashboardCardSpan, resolveDashboardCardOrder
} from '../utils/DashboardUtils';
import { feedbackService } from '../services/FeedbackService';
import { publicNetworkService } from '../services/LocalNetworkService';
import { vpnService } from '../services/VpnService';
import { profileStore } from '../stores/ProfileStore';
import { runtimeStore } from '../stores/RuntimeStore';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import {
  resolveResponsiveMetrics,
  resolveContentWidth, proxyGroupColumnCount
} from '../utils/ResponsiveUtils';
import {
  CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, HEADER_ACTION_SIZE, HEADER_ACTION_ICON_SIZE
} from '../constants/UiConstants';
import { PageHeader } from '../components/PageHeader';
import { FadingScrollLayout } from '../components/FadingScrollLayout';
import { AppPage } from '../model/NavigationModels';
import { navigationIntentService } from '../services/NavigationIntentService';

import { DASHBOARD_CARD_RADIUS, DASHBOARD_CARD_PADDING } from '../constants/DashboardConstants';
import { visibleProxyGroups } from '../utils/RuntimeUtils';
import { selectionAnimation } from '../utils/AnimationUtils';

const MODES: RuntimeMode[] = [RuntimeMode.RULE, RuntimeMode.GLOBAL, RuntimeMode.DIRECT];
const VIEW_SYNC_INTERVAL_MS = 1000;

/** 仪表盘按默认顺序聚合运行状态；用户操作交给 Store 与服务完成。 */
@Component
export struct DashboardPage {
  @StorageProp('appTheme') @Watch('onThemeChange') theme: AppTheme = DEFAULT_APP_THEME;
  @StorageProp('appForeground') @Watch('updateActivity') foreground: boolean = false;
  @Prop @Watch('updateActivity') isActive: boolean = true;
  @State headerInset: number = 0;
  @State coreState: CoreServiceState = vpnService.getCoreState();
  @State proxyState: ProxyState = vpnService.getProxyState();
  @State message: string = vpnService.getLastMessage();
  @State activeProfile: Profile | undefined = undefined;
  @State profiles: Profile[] = [];
  @State profileOperation: boolean = false;
  @State runtime: DashboardSnapshot | undefined = undefined;
  @State history: TrafficSample[] = [];
  @State publicIpv4: string = '未知';
  @State publicCountry: string = '未知地区';
  @State publicCountryCode: string = '';
  @State publicOrganization: string = '';
  @State publicNetworkType: IpNetworkType = IpNetworkType.UNKNOWN;
  @State publicIpQuality: IpQuality = IpQuality.UNKNOWN;
  @State publicIpRiskScore: number | undefined = undefined;
  @State publicIpQualityError: string = '';
  @State groups: ProxyGroupSnapshot[] = [];
  @State requestCount: number = 0;
  @State contentWidth: number = 0;
  @State statusCardHeight: number = 0;
  @State fontScale: number = 1;
  @State @Watch('updateCountryRotation') publicNetworkChecking: boolean = true;
  @State countryRotation: number = 0;
  @State publicNetworkError: string = '';
  @State restarting: boolean = false;
  @State selectedMode: RuntimeMode = DEFAULT_RUNTIME_MODE;
  @State runtimeBusyKey: string = '';
  @State sessionStartedAt: number = 0;
  @State sessionEndedAt: number = 0;
  @State runtimeProfileId: string = '';
  @State profileBusy: boolean = false;
  @State proxyOperation: boolean = false;
  @State elapsedSeconds: number = 0;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  @State cardOrder: DashboardCard[] = resolveDashboardCardOrder(true);
  private unsubscribeNetwork: (() => void) | undefined = undefined;
  private unsubscribeLifecycle: (() => void) | undefined = undefined;
  private unsubscribeProfile: (() => void) | undefined = undefined;
  private viewSyncTimer: number | undefined = undefined;
  private lastTrafficSampleTimestamp: number = 0;
  private alertDialog: CustomDialogController | undefined;

  aboutToAppear(): void {
    this.updateActivity();
  }

  aboutToDisappear(): void { this.stopObserving(); }

  private updateActivity(): void {
    this.stopObserving();
    if (!this.isActive || !this.foreground) { return; }
    this.unsubscribeProfile = profileStore.subscribe((snapshot: ProfileStoreSnapshot): void => {
      this.profiles = snapshot.profiles;
      this.activeProfile = snapshot.profiles.find((profile: Profile): boolean => profile.id === snapshot.activeProfileId);
      this.profileBusy = snapshot.busyProfileId.length > 0;
    });
    this.unsubscribeLifecycle = vpnService.subscribeLifecycle((snapshot: RuntimeLifecycleSnapshot): void => {
      this.applyLifecycle(snapshot);
    });
    this.unsubscribeNetwork = publicNetworkService.subscribe((snapshot: PublicNetworkSnapshot): void => {
      this.applyPublicNetworkSnapshot(snapshot);
    });
    this.syncViewState();
    this.viewSyncTimer = setInterval((): void => this.syncViewState(), VIEW_SYNC_INTERVAL_MS);
    this.updateCountryRotation();
    runtimeStore.refresh();
  }

  private stopObserving(): void {
    this.stopCountryRotation();
    this.alertDialog?.close();
    this.unsubscribeProfile?.();
    this.unsubscribeProfile = undefined;
    this.unsubscribeLifecycle?.();
    this.unsubscribeLifecycle = undefined;
    this.unsubscribeNetwork?.();
    this.unsubscribeNetwork = undefined;
    if (this.viewSyncTimer !== undefined) {
      clearInterval(this.viewSyncTimer);
      this.viewSyncTimer = undefined;
    }
  }

  // 每秒刷新计时和展示快照，仅在新流量样本到达时替换图表数据，避免重复绘制。
  private syncViewState(): void {
    const lifecycle = vpnService.getLifecycleSnapshot();
    this.applyLifecycle(lifecycle);
    const runtimeSnapshot = runtimeStore.getSnapshot();
    this.runtime = runtimeSnapshot.dashboard;
    this.groups = visibleProxyGroups(runtimeSnapshot.proxies, runtimeSnapshot.proxyMode);
    this.requestCount = runtimeSnapshot.requests.length;
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

  private applyLifecycle(snapshot: RuntimeLifecycleSnapshot): void {
    this.coreState = snapshot.coreState;
    this.proxyState = snapshot.proxyState;
    this.message = snapshot.message;
    this.runtimeProfileId = snapshot.profileId;
    this.sessionStartedAt = snapshot.sessionStartedAt;
    this.sessionEndedAt = snapshot.sessionEndedAt;
    this.updateElapsedSeconds();
  }

  private applyPublicNetworkSnapshot(snapshot: PublicNetworkSnapshot): void {
    this.publicIpv4 = snapshot.publicIpv4;
    this.publicCountry = snapshot.country;
    this.publicCountryCode = snapshot.countryCode;
    this.publicOrganization = snapshot.organization ?? '';
    this.publicNetworkType = snapshot.networkType ?? IpNetworkType.UNKNOWN;
    this.publicIpQuality = snapshot.quality ?? IpQuality.UNKNOWN;
    this.publicIpRiskScore = snapshot.riskScore;
    this.publicIpQualityError = snapshot.qualityError ?? '';
    this.publicNetworkChecking = snapshot.checking;
    this.publicNetworkError = snapshot.errorMessage;
  }

  private updateCountryRotation(): void {
    this.stopCountryRotation();
    if (this.isActive && this.foreground && this.publicNetworkChecking && selectionAnimation().duration !== 0) {
      this.getUIContext().animateTo({ duration: 1600, curve: Curve.Linear, iterations: -1 }, (): void => {
        this.countryRotation = 360;
      });
    }
  }

  private stopCountryRotation(): void {
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      this.countryRotation = 0;
    });
  }

  private ipTypeLabel(): string {
    switch (this.publicNetworkType) {
      case IpNetworkType.HOSTING: return '机房';
      case IpNetworkType.MOBILE: return '移动';
      case IpNetworkType.NON_HOSTING: return '非机房';
      default: return '类型未知';
    }
  }

  private ipQualityLabel(): string {
    if (this.publicNetworkChecking) { return '质量 校验中'; }
    switch (this.publicIpQuality) {
      case IpQuality.GOOD: return '质量 优';
      case IpQuality.NORMAL: return '质量 普通';
      case IpQuality.POOR: return '质量 较差';
      default: return '质量 未知';
    }
  }

  private ipQualityColor(): ResourceColor {
    return this.publicIpQuality === IpQuality.GOOD ? $r('app.color.dashboard_success_text') :
      (this.publicIpQuality === IpQuality.POOR ? $r('app.color.status_error') : $r('app.color.content_secondary'));
  }

  private ipQualityBackground(): ResourceColor {
    return this.publicIpQuality === IpQuality.GOOD ? $r('app.color.dashboard_success_surface') :
      (this.publicIpQuality === IpQuality.POOR ? $r('app.color.status_error_surface') : this.theme.inset);
  }

  private updateWidth(width: Length): void {
    const wasCompact = this.isCompact();
    this.contentWidth = resolveContentWidth(width);
    this.metrics = resolveResponsiveMetrics(this.contentWidth);
    this.fontScale = this.theme.fontScale || this.getUIContext().fp2px(1) / this.getUIContext().vp2px(1);
    if (wasCompact !== this.isCompact()) {
      this.cardOrder = resolveDashboardCardOrder(this.isCompact());
    }
  }

  private onThemeChange(): void { this.updateWidth(this.contentWidth); }

  private isCompact(): boolean {
    return proxyGroupColumnCount(this.contentWidth, this.fontScale) === 1;
  }

  private canToggleProxy(): boolean {
    return !this.isProxyBusy() && !this.isCoreBusy() && !this.profileBusy && (this.isProxyActive() ||
      (this.coreState === CoreServiceState.RUNNING && this.runtimeProfileId.length > 0 &&
        this.runtimeProfileId === this.activeProfile?.id));
  }

  private isProxyBusy(): boolean {
    return this.proxyOperation || this.proxyState === ProxyState.ENABLING || this.proxyState === ProxyState.DISABLING;
  }

  private isCoreBusy(): boolean {
    return this.restarting || this.coreState === CoreServiceState.STARTING ||
      this.coreState === CoreServiceState.RELOADING;
  }

  private isProxyActive(): boolean {
    return this.proxyState === ProxyState.ENABLED || this.proxyState === ProxyState.ENABLING;
  }

  private async toggleProxy(enabled: boolean): Promise<void> {
    if (this.isProxyBusy() || this.isCoreBusy() || this.profileBusy) {
      return;
    }
    this.proxyOperation = true;
    try {
      if (!enabled) {
        await vpnService.stop();
      } else if (this.activeProfile === undefined) {
        feedbackService.warning('请先添加并选择一份配置');
      } else {
        await vpnService.start();
      }
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    } finally {
      this.proxyOperation = false;
      this.syncViewState();
    }
  }

  private coreStatus(): string {
    if (this.restarting) {
      return 'Core 重启中';
    }
    if (this.coreState === CoreServiceState.RUNNING) {
      return 'Core 运行中';
    }
    if (this.coreState === CoreServiceState.STARTING) {
      return 'Core 启动中';
    }
    if (this.coreState === CoreServiceState.RELOADING) {
      return 'Core 重启中';
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

  private coreStatusIcon(): Resource {
    switch (this.coreState) {
      case CoreServiceState.RUNNING: return $r('app.media.action_check');
      case CoreServiceState.ERROR: return $r('app.media.core_error');
      case CoreServiceState.WAITING_CONFIG: return $r('app.media.nav_configuration');
      default: return $r('app.media.ic_public_pause');
    }
  }

  private coreStatusColor(): ResourceColor {
    return this.coreState === CoreServiceState.RUNNING ? $r('app.color.status_success') :
      (this.coreState === CoreServiceState.ERROR ? $r('app.color.status_error') : $r('app.color.content_secondary'));
  }

  private async updateActiveProfile(): Promise<void> {
    const profile = this.activeProfile;
    if (profile === undefined || profile.type !== ProfileType.SUBSCRIPTION || this.profileBusy || this.profileOperation) {
      return;
    }
    this.profileOperation = true;
    try {
      await profileStore.update(profile.id);
      feedbackService.success('订阅已更新并通过校验');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    } finally {
      this.profileOperation = false;
    }
  }

  private async selectProfile(id: string): Promise<void> {
    if (id === this.activeProfile?.id || this.profileBusy || this.profileOperation) { return; }
    this.profileOperation = true;
    try {
      await profileStore.select(id);
      feedbackService.success('已切换活动配置');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    } finally {
      this.profileOperation = false;
    }
  }

  private profileChoices(): MenuElement[] {
    return this.profiles.map((profile: Profile): MenuElement => ({
      value: `${profile.name}${profile.id === this.activeProfile?.id ? '（当前）' : ''}`,
      enabled: !this.profileBusy && !this.profileOperation && profile.id !== this.activeProfile?.id,
      action: (): void => { this.selectProfile(profile.id); }
    }));
  }

  @Builder
  private profileMenu() {
    themeMenu(this.profileChoices(), this.theme)
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
    if (this.isCoreBusy() || this.isProxyBusy() || this.profileBusy) {
      return;
    }
    if (!this.isProxyActive()) {
      this.restartCore();
      return;
    }
    this.alertDialog = new CustomDialogController({
      builder: ThemeAlertDialog({ title: '重启 Core',
        message: '重启会短暂中断代理，完成后自动恢复。本次使用时长将继续累计。',
        confirmLabel: '重启', onConfirm: (): void => { this.restartCore(); } }),
      customStyle: true, alignment: DialogAlignment.Center
    });
    this.alertDialog.open();
  }

  private async restartCore(): Promise<void> {
    if (this.isCoreBusy() || this.isProxyBusy() || this.profileBusy) {
      return;
    }
    this.restarting = true;
    try {
      await vpnService.restart();
      const active = this.activeProfile;
      if (active !== undefined) {
        await vpnService.applyProfile(active.id, active.localPath,
          `${active.id}:${active.localPath}:${active.updatedAt}`);
      }
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    } finally {
      this.restarting = false;
      this.syncViewState();
    }
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : '操作失败';
  }

  private updateElapsedSeconds(): void {
    this.elapsedSeconds = proxySessionElapsedSeconds(this.sessionStartedAt, this.sessionEndedAt,
      systemDateTime.getUptime(systemDateTime.TimeType.STARTUP));
  }


  private proxyStatus(): string {
    switch (this.proxyState) {
      case ProxyState.ENABLED: return '已连接';
      case ProxyState.ENABLING: return '连接中…';
      case ProxyState.DISABLING: return '断开中…';
      case ProxyState.ERROR: return '连接异常';
      default: return '未连接';
    }
  }

  private hasStatusError(): boolean {
    return this.coreState === CoreServiceState.ERROR || this.proxyState === ProxyState.ERROR ||
      this.message.startsWith('配置应用失败');
  }

  private headerHint(): string {
    if (this.hasStatusError()) {
      return this.message || '连接异常，请重试';
    }
    if (this.runtimeProfileId.length === 0 && this.coreState === CoreServiceState.RUNNING) {
      return '请选择配置';
    }
    return this.proxyStatus();
  }

  @Builder
  private headerActions() {
    Row({ space: 16 }) {
      Button({ type: ButtonType.Normal }) {
        if (this.isCoreBusy()) {
          LoadingProgress().width(HEADER_ACTION_ICON_SIZE).height(HEADER_ACTION_ICON_SIZE)
            .color($r('app.color.content_secondary'))
        } else {
          Image(this.coreStatusIcon()).width(HEADER_ACTION_ICON_SIZE).height(HEADER_ACTION_ICON_SIZE)
            .fillColor(this.coreStatusColor()).accessibilityLevel('no')
        }
      }
      .id('dashboard-core-status')
      .width(HEADER_ACTION_SIZE).height(HEADER_ACTION_SIZE).padding(0).borderRadius(16)
      .responseRegion({ x: -8, y: -8, width: CONTROL_HEIGHT, height: CONTROL_HEIGHT })
      .backgroundColor(this.theme.muted)
      .enabled(!this.isCoreBusy() && !this.isProxyBusy() && !this.profileBusy)
      .accessibilityText(`${this.coreStatus()}，点击重启 Core`)
      .onClick((): void => { this.confirmCoreRestart(); })

    }
  }

  @Builder
  private cardTitle(icon: Resource, title: string) {
    Row({ space: 8 }) {
      Image(icon).width(18).height(18).fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
      Text(title).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary'))
    }
    .constraintSize({ minHeight: 24 })
  }

  @Builder
  private chevron() {
    Image($r('app.media.action_chevron_down')).width(18).height(18).rotate({ angle: -90 })
      .fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
  }

  @Builder
  private modeButtons() {
    Row({ space: 4 }) {
      ForEach(MODES, (mode: RuntimeMode) => {
        Button({ type: ButtonType.Normal }) {
          Column({ space: 4 }) {
            Image(mode === RuntimeMode.RULE ? $r('app.media.nav_requests') :
              (mode === RuntimeMode.GLOBAL ? $r('app.media.public_network') : $r('app.media.action_locate')))
              .width(18).height(18)
              .fillColor(this.selectedMode === mode ? this.theme.onAccent : $r('app.color.content_secondary'))
              .accessibilityLevel('no')
            Text(this.modeLabel(mode)).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
              .fontColor(this.selectedMode === mode ? this.theme.onAccent : $r('app.color.content_secondary'))
          }
          .padding({ top: 8, bottom: 8 })
        }
        .id(`dashboard-mode-${mode}`)
        .layoutWeight(1).constraintSize({ minHeight: 56 }).padding(0).borderRadius(28)
        .backgroundColor(this.selectedMode === mode ? this.theme.accent : this.theme.inset)
        .enabled(this.coreState === CoreServiceState.RUNNING && !this.profileBusy &&
          !this.isCoreBusy() && !this.isProxyBusy() && this.runtimeBusyKey.length === 0)
        .accessibilityText(`出站模式：${this.modeLabel(mode)}`)
        .accessibilitySelected(this.selectedMode === mode)
        .onClick((): void => { this.setMode(mode); })
      }, (mode: RuntimeMode): string => mode)
    }
    .width('100%')
  }

  @Builder
  private modeCard() {
    if (this.isCompact()) {
      Column({ space: 16 }) {
        this.cardTitle($r('app.media.nav_proxy'), '出站模式')
        this.modeButtons()
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding(DASHBOARD_CARD_PADDING)
      .borderRadius(DASHBOARD_CARD_RADIUS).backgroundColor(this.theme.surface)
    } else {
      Row({ space: 20 }) {
        this.cardTitle($r('app.media.nav_proxy'), '出站模式')
        Column() { this.modeButtons() }.layoutWeight(1)
      }
      .width('100%').padding({ left: DASHBOARD_CARD_PADDING, right: 12, top: 12, bottom: 12 })
      .borderRadius(DASHBOARD_CARD_RADIUS).backgroundColor(this.theme.surface)
    }
  }

  @Builder
  private proxyButton() {
    Button({ type: ButtonType.Normal }) {
      Stack() {
        Row().width('76%').height('76%').borderRadius(100).backgroundColor(this.theme.accent)
          .shadow({ radius: this.getUIContext().vp2px(10), color: this.theme.accentGlow, offsetY: 5 })
          .accessibilityLevel('no')
        if (this.proxyState === ProxyState.ENABLED || this.proxyState === ProxyState.DISABLING) {
          Image($r('app.media.dashboard_bloom')).width('100%').height('100%')
            .fillColor(this.theme.accent).accessibilityLevel('no')
        } else {
          Row().width('100%').height('100%').borderRadius(100)
            .backgroundColor(this.theme.accent).accessibilityLevel('no')
        }
        if (this.isProxyBusy()) {
          LoadingProgress().width(26).height(26).color(this.theme.onAccent)
        } else {
          Image(this.isProxyActive() ? $r('app.media.ic_public_pause') : $r('app.media.ic_public_play'))
            .width(this.isCompact() ? 24 : 30).height(this.isCompact() ? 24 : 30)
            .fillColor(this.theme.onAccent).accessibilityLevel('no')
        }
      }
      .width('100%').height('100%')
    }
    .id('dashboard-proxy-toggle')
    .width(this.isCompact() ? 64 : 96).height(this.isCompact() ? 64 : 96).padding(0)
    .backgroundColor(Color.Transparent).borderRadius(24)
    .enabled(this.canToggleProxy()).opacity(this.canToggleProxy() ? 1 : 0.45)
    .accessibilityText(this.isProxyBusy() ? '正在切换 VPN 代理' : (this.isProxyActive() ? '关闭 VPN 代理' : '开启 VPN 代理'))
    .onClick((): void => { this.toggleProxy(!this.isProxyActive()); })
  }

  @Builder
  private countryRefreshButton() {
    Button({ type: ButtonType.Normal }) {
      Stack() {
        Image($r('app.media.dashboard_clover')).width('100%').height('100%')
          .fillColor(this.theme.muted).accessibilityLevel('no')
          .rotate({ angle: this.countryRotation })
          .onAppear((): void => { this.updateCountryRotation(); })
          .onDisAppear((): void => { this.stopCountryRotation(); })
        Text(this.publicCountryCode || '—').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary')).maxLines(1)
      }
      .width('100%').height('100%')
    }
    .id('dashboard-ip-refresh').width(this.isCompact() ? 44 : 52).height(this.isCompact() ? 44 : 52)
    .padding(0).backgroundColor(Color.Transparent).borderRadius(12).enabled(!this.publicNetworkChecking)
    .accessibilityText(`${this.publicCountry} ${this.publicCountryCode}，${this.publicNetworkChecking ? '正在刷新 IP 信息' : '刷新 IP 信息'}`)
    .onClick((): void => { publicNetworkService.refresh(); })
  }

  @Builder
  private publicNetworkCard() {
    Stack({ alignContent: Alignment.End }) {
      // 背景跟随正文实测高度，避免宽屏和大字号下出现上下边带。
      Image($r('app.media.dashboard_status_wave')).width(this.isCompact() ? '48%' : '40%')
        .height(this.statusCardHeight)
        .objectFit(ImageFit.Fill).supportSvg2(true)
        .fillColor(this.isProxyActive() ? this.theme.accentSurface : this.theme.inset)
        .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
      this.publicNetworkContent()
    }
    .width('100%').backgroundColor(this.theme.surface)
    .borderRadius(DASHBOARD_CARD_RADIUS).clip(true)
  }

  @Builder
  private publicNetworkContent() {
    Column({ space: 20 }) {
      Row({ space: 14 }) {
        Column({ space: 14 }) {
          Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center,
            space: { main: LengthMetrics.vp(8), cross: LengthMetrics.vp(4) } }) {
            this.cardTitle($r('app.media.dashboard_status'), '状态')
            Row({ space: 5 }) {
              if (this.isProxyActive() && !this.hasStatusError()) {
                Row().width(5).height(5).borderRadius(3).backgroundColor($r('app.color.dashboard_success_text'))
                  .accessibilityLevel('no')
              }
              Text(this.hasStatusError() ? '异常' : (this.isProxyBusy() ? this.proxyStatus() :
                (this.isProxyActive() ? '运行中' : '未运行')))
                .fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
                .fontColor(this.hasStatusError() ? $r('app.color.status_error') :
                  (this.isProxyActive() ? $r('app.color.dashboard_success_text') : $r('app.color.content_secondary')))
            }
            .padding({ left: 9, right: 9, top: 4, bottom: 4 }).borderRadius(16)
            .backgroundColor(this.hasStatusError() ? $r('app.color.status_error_surface') :
              (this.isProxyActive() ? $r('app.color.dashboard_success_surface') : this.theme.inset))
          }
          .width('100%')
          Row({ space: 10 }) {
            this.countryRefreshButton()
            Column({ space: 4 }) {
              Text(this.publicIpv4 === '未知' ? '—' : this.publicIpv4)
                .id('dashboard-public-ip').fontSize(themeFontSize(this.isCompact() ? 22 : 30, this.theme))
                .fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.content_primary')).width('100%')
                .maxLines(this.fontScale > 1.2 ? 2 : 1).minFontSize(themeFontSize(14, this.theme))
                .maxFontSize(themeFontSize(this.isCompact() ? 22 : 30, this.theme))
                .heightAdaptivePolicy(TextHeightAdaptivePolicy.MIN_FONT_SIZE_FIRST)
              Flex({ wrap: FlexWrap.Wrap,
                space: { main: LengthMetrics.vp(5), cross: LengthMetrics.vp(4) } }) {
                Text(this.ipTypeLabel()).id('dashboard-ip-type').fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily)
                  .fontColor($r('app.color.content_secondary')).backgroundColor(this.theme.inset)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(14)
                Text(this.ipQualityLabel()).id('dashboard-ip-quality').fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily)
                  .fontColor(this.ipQualityColor()).backgroundColor(this.ipQualityBackground())
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(14)
                  .accessibilityDescription(this.publicIpRiskScore === undefined ? '尚无有效的 IP 风险评估' :
                    `IPQuery 风险分 ${this.publicIpRiskScore}/100，分数越低风险越低；质量为参考评级`)
              }
              .width('100%')
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.proxyButton()
      }
      .width('100%').alignItems(VerticalAlign.Center)
      Row({ space: 20 }) {
        Column({ space: 4 }) {
          Text('运行时长').fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
          Text(this.sessionStartedAt > 0 ? formatVpnRunDuration(this.elapsedSeconds) : '—')
            .fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary'))
        }
        .alignItems(HorizontalAlign.Start)
        Column({ space: 4 }) {
          Text('组织').fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
          Text(this.publicOrganization || '—').id('dashboard-ip-organization')
            .fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary'))
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start).layoutWeight(1)
      }
      .width('100%').alignItems(VerticalAlign.Top)
      if (!this.publicNetworkChecking && (this.publicNetworkError || this.publicIpQualityError)) {
        Text(this.publicNetworkError || this.publicIpQualityError).fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_secondary')).width('100%')
      }
      if (this.hasStatusError()) {
        Text(this.headerHint()).fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.status_error')).width('100%')
      }
    }
    .padding(DASHBOARD_CARD_PADDING).width('100%').alignItems(HorizontalAlign.Start)
    .onAreaChange((_old: Area, area: Area): void => { this.statusCardHeight = Number(area.height); })
  }

  @Builder
  private vpnCard() {
    Row({ space: 12 }) {
      Stack() {
        Image($r('app.media.dashboard_bloom')).width(44).height(44).fillColor(this.theme.accent)
        Image($r('app.media.dashboard_shield')).width(24).height(24).fillColor(this.theme.onAccent)
      }
      .accessibilityLevel('no')
      Column({ space: 2 }) {
        Text('VPN').fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary'))
        Text(this.proxyStatus()).fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isProxyActive() })
        .id('dashboard-vpn-switch').selectedColor(this.theme.accent)
        .enabled(this.canToggleProxy()).accessibilityText('VPN 代理')
        .onChange((enabled: boolean): void => { this.toggleProxy(enabled); })
    }
    .width('100%').padding({ left: DASHBOARD_CARD_PADDING, right: DASHBOARD_CARD_PADDING, top: 16, bottom: 16 })
    .borderRadius(DASHBOARD_CARD_RADIUS).backgroundColor(this.theme.surface)
  }

  @Builder
  private speedTiles() {
    GridRow({ columns: this.fontScale > 1.2 ? 1 : 2, gutter: 12 }) {
      GridCol() {
        RuntimeSpeedCard({ runtime: this.runtime, history: this.history, proxyState: this.proxyState,
          upload: true, compact: this.isCompact() })
      }
      GridCol() {
        RuntimeSpeedCard({ runtime: this.runtime, history: this.history, proxyState: this.proxyState,
          upload: false, compact: this.isCompact() })
      }
    }
    .width('100%')
  }

  @Builder
  private speedCard() {
    if (this.isCompact()) {
      Column({ space: 12 }) {
        this.cardTitle($r('app.media.network_speed'), '网络速度')
        this.speedTiles()
      }
      .width('100%').alignItems(HorizontalAlign.Start).padding(DASHBOARD_CARD_PADDING)
      .borderRadius(DASHBOARD_CARD_RADIUS).backgroundColor(this.theme.surface)
    } else {
      this.speedTiles()
    }
  }

  @Builder
  private configurationCard() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        this.cardTitle($r('app.media.nav_configuration'), '配置')
        Blank()
        if (this.activeProfile?.type === ProfileType.SUBSCRIPTION) {
          Button({ type: ButtonType.Circle }) {
            if (this.profileBusy || this.profileOperation) {
              LoadingProgress().width(18).height(18).color(this.theme.accent)
            } else {
              Image($r('app.media.action_refresh')).width(18).height(18)
                .fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
            }
          }
          .id('dashboard-profile-refresh').width(44).height(44).padding(12).backgroundColor(Color.Transparent)
          .enabled(!this.profileBusy && !this.profileOperation).accessibilityText('更新当前订阅')
          .onClick((): void => { this.updateActiveProfile(); })
        }
        Button({ type: ButtonType.Circle }) { this.chevron() }
          .id('dashboard-profile-open').width(44).height(44).padding(12).backgroundColor(Color.Transparent)
          .accessibilityText('打开配置页')
          .onClick((): void => { navigationIntentService.publish(AppPage.CONFIGURATION); })
      }
      .width('100%').margin({ top: -10, bottom: -8, right: -10 })
      if (this.activeProfile === undefined) {
        Button('添加配置', { type: ButtonType.Normal })
          .fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary'))
          .height(44).padding(0).backgroundColor(Color.Transparent)
          .onClick((): void => { navigationIntentService.publish(AppPage.CONFIGURATION); })
      } else {
        Column({ space: 4 }) {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              Text(this.activeProfile.name).fontSize(themeFontSize(18, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.content_primary')).maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).flexShrink(1)
              Image($r('app.media.action_switch')).width(20).height(20)
                .fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
            }
            .constraintSize({ minHeight: 44 }).justifyContent(FlexAlign.Start)
          }
          .id('dashboard-profile-switch').constraintSize({ maxWidth: '100%' }).padding(0)
          .backgroundColor(Color.Transparent).borderRadius(8).align(Alignment.Start)
          .enabled(!this.profileBusy && !this.profileOperation)
          .accessibilityText(`当前配置 ${this.activeProfile.name}，切换配置`)
          .bindMenu(this.profileMenu(), { backgroundColor: this.theme.surface })
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween,
            space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(4) } }) {
            Text(this.activeProfile.type === ProfileType.LOCAL ? '本地配置' :
              `更新于 ${formatProfileRelativeTime(this.activeProfile.lastUpdateAt)}`)
              .fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
            if (this.activeProfile.type === ProfileType.SUBSCRIPTION) {
              Text(formatProfileRemainingDays(this.activeProfile.expireAt))
                .fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
            }
          }
          .width('100%')
        }
        .width('100%').alignItems(HorizontalAlign.Start)
        if ((this.activeProfile.totalBytes ?? 0) > 0) {
          Column({ space: 8 }) {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween, alignItems: ItemAlign.Center,
              space: { main: LengthMetrics.vp(12), cross: LengthMetrics.vp(4) } }) {
              Text() {
                Span(`${Math.round(profileUsageRatio(this.activeProfile) * 100)}%`).fontSize(themeFontSize(20, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold)
                Span(' 已用').fontSize(themeFontSize(13, this.theme)).fontFamily(this.theme.fontFamily)
              }
              .fontColor($r('app.color.content_primary'))
              Text(`${formatProfileBytes((this.activeProfile.uploadBytes ?? 0) + (this.activeProfile.downloadBytes ?? 0)).replace(/([KMGT]?B)$/, ' $1')}` +
                ` / ${formatProfileBytes(this.activeProfile.totalBytes ?? 0).replace(/([KMGT]?B)$/, ' $1')}`)
                .fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
            }
            .width('100%')
            SubscriptionUsageBar({ ratio: profileUsageRatio(this.activeProfile) })
          }
          .width('100%').alignItems(HorizontalAlign.Start).margin({ top: 8 })
        } else if (this.activeProfile.type === ProfileType.SUBSCRIPTION) {
          Text('未提供流量信息').fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
        }
      }
    }
    .width('100%').alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.SpaceBetween)
    .constraintSize({ minHeight: this.isCompact() ? 0 : 196 })
    .padding(DASHBOARD_CARD_PADDING).borderRadius(DASHBOARD_CARD_RADIUS)
    .backgroundColor(this.theme.surface)
  }

  @Builder
  private serviceTile(icon: Resource, label: string, value: string, available: boolean) {
    Row({ space: 8 }) {
      Image(icon).width(24).height(24).fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
      Column({ space: 4 }) {
        Text(label).fontSize(themeFontSize(13, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary'))
        Text(value).fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor(available ? $r('app.color.proxy_delay_success') : $r('app.color.content_secondary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start).layoutWeight(1)
    }
    .layoutWeight(1).constraintSize({ minHeight: 58 }).padding(10)
    .borderRadius(20).backgroundColor(this.theme.inset).accessibilityGroup(true)
  }

  @Builder
  private servicesCard() {
    Column({ space: 16 }) {
      this.cardTitle($r('app.media.dashboard_shield'), '服务状态')
      Column({ space: 8 }) {
        Row({ space: 8 }) {
          this.serviceTile($r('app.media.runtime_memory'), 'Core', this.coreStatus().replace('Core ', ''),
            this.coreState === CoreServiceState.RUNNING)
          this.serviceTile($r('app.media.dashboard_shield'), 'VPN', this.proxyStatus(), this.proxyState === ProxyState.ENABLED)
        }
        .width('100%')
        Row({ space: 8 }) {
          this.serviceTile($r('app.media.nav_configuration'), '配置', this.activeProfile === undefined ? '未选择' : '已选择',
            this.activeProfile !== undefined)
          this.serviceTile($r('app.media.public_network'), '公网出口', this.publicNetworkChecking ? '查询中' :
            (this.publicNetworkError.length > 0 ? '查询失败' : (this.publicIpv4 === '未知' ? '待查询' : '已获取')),
            !this.publicNetworkChecking && this.publicNetworkError.length === 0 && this.publicIpv4 !== '未知')
        }
        .width('100%')
      }
      .width('100%')
    }
    .width('100%').alignItems(HorizontalAlign.Start).padding(DASHBOARD_CARD_PADDING)
    .borderRadius(DASHBOARD_CARD_RADIUS).backgroundColor(this.theme.surface)
  }

  @Builder
  private groupsCard() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 20 }) {
        Row() {
          this.cardTitle($r('app.media.nav_proxy'), '策略组')
          Blank()
          this.chevron()
        }
        .width('100%')
        if (this.groups.length === 0) {
          Column({ space: 12 }) {
            Stack() {
              Image($r('app.media.dashboard_bloom')).width(56).height(56)
                .fillColor(this.theme.inset)
              Image($r('app.media.nav_proxy')).width(26).height(26).fillColor($r('app.color.content_secondary'))
            }
            .accessibilityLevel('no')
            Text('暂无策略组').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
          }
          .width('100%').padding({ top: 12, bottom: 12 })
        } else {
          Row({ space: 12 }) {
            Text(`${this.groups.length}`).fontSize(themeFontSize(36, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold).fontColor($r('app.color.content_primary'))
            Text('个').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
            Blank()
            Row({ space: -8 }) {
              ForEach(this.groups.slice(0, 3), (group: ProxyGroupSnapshot) => {
                Text(group.name.substring(0, 1).toUpperCase()).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.content_secondary')).textAlign(TextAlign.Center)
                  .width(36).height(40).borderRadius(14)
                  .backgroundColor(this.theme.inset)
                  .border({ width: 2, color: this.theme.surface })
              }, (group: ProxyGroupSnapshot): string => group.name)
              if (this.groups.length > 3) {
                Text(`+${this.groups.length - 3}`).fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.content_secondary')).textAlign(TextAlign.Center)
                  .width(36).height(40).borderRadius(14).backgroundColor(this.theme.inset)
                  .border({ width: 2, color: this.theme.surface })
              }
            }
            .accessibilityLevel('no')
          }
          .width('100%')
        }
      }
      .width('100%').alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.SpaceBetween)
      .constraintSize({ minHeight: this.isCompact() ? 80 : 136 })
    }
    .width('100%').padding(DASHBOARD_CARD_PADDING).borderRadius(DASHBOARD_CARD_RADIUS)
    .backgroundColor(this.theme.surface)
    .accessibilityText(`${this.groups.length} 个策略组，打开代理页`)
    .onClick((): void => { navigationIntentService.publish(AppPage.PROXY); })
  }

  @Builder
  private cardContent(card: DashboardCard) {
    if (card === DashboardCard.MODE) {
      this.modeCard()
    } else if (card === DashboardCard.CONFIGURATION) {
      this.configurationCard()
    } else if (card === DashboardCard.PUBLIC_NETWORK) {
      this.publicNetworkCard()
    } else if (card === DashboardCard.SPEED) {
      this.speedCard()
    } else if (card === DashboardCard.VPN) {
      this.vpnCard()
    } else if (card === DashboardCard.SERVICES) {
      this.servicesCard()
    } else if (card === DashboardCard.GROUPS) {
      this.groupsCard()
    } else if (card === DashboardCard.CONNECTIONS) {
      RuntimeStatusCard({ runtime: this.runtime, requestCount: this.requestCount })
    } else if (card === DashboardCard.MEMORY) {
      RuntimeMemoryCard({ runtime: this.runtime, isActive: this.isActive, cardHeight: this.isCompact() ? 148 : 176 })
    }
  }

  @Builder
  private scrollContent() {
    Scroll() {
      GridRow({ columns: 2, gutter: { x: 16, y: 12 } }) {
        ForEach(this.cardOrder, (card: DashboardCard) => {
          GridCol({ span: dashboardCardSpan(card, this.isCompact()) }) {
            this.cardContent(card)
          }
          .id(`dashboard-card-${card}`).borderRadius(DASHBOARD_CARD_RADIUS)
          .shadow({ radius: 12, color: $r('app.color.dashboard_shadow'), offsetY: 4 })
        }, (card: DashboardCard): string => card)
      }
      .padding({ top: this.headerInset, left: this.metrics.pagePadding, right: this.metrics.pagePadding,
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET })
    }
    .id('dashboard-scroll').width('100%').height('100%').scrollBar(BarState.Off)
    .align(Alignment.Top).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private pageHeader() {
    PageHeader({
      title: $r('app.string.nav_dashboard'), contentPadding: this.metrics.pagePadding,
      actions: (): void => { this.headerActions(); }
    })
  }

  build() {
    FadingScrollLayout({
      topInset: $headerInset,
      surface: this.theme.background,
      transparentSurface: this.theme.transparentBackground, gap: 20,
      header: (): void => { this.pageHeader(); },
      content: (): void => { this.scrollContent(); }
    })
    .onAreaChange((_old: Area, area: Area): void => { this.updateWidth(area.width); })
  }
}
