import { RuntimeStatusCard } from './RuntimeStatusCard';
import { RuntimeTrafficCard } from './RuntimeTrafficCard';
import { RuntimeSpeedCard } from './RuntimeSpeedCard';
import { RuntimeDurationCard } from './RuntimeDurationCard';
import { RuntimeMemoryCard } from './RuntimeMemoryCard';
import { systemDateTime } from '@kit.BasicServicesKit';
import { Profile, ProfileStoreSnapshot } from '../model/ProfileModels';
import { DashboardSnapshot, PublicNetworkSnapshot, RuntimeMode, TrafficSample } from '../model/RuntimeModels';
import { DEFAULT_RUNTIME_MODE } from '../constants/RuntimeConstants';
import { CoreServiceState, ProxyState, RuntimeLifecycleSnapshot } from '../model/VpnModels';
import { proxySessionElapsedSeconds } from '../utils/VpnUtils';
import { profileUsageRatio } from '../utils/ProfileUtils';
import { DashboardCard } from '../model/DashboardModels';
import { SettingsStoreSnapshot } from '../model/SettingsModels';
import {
  dashboardCardLabel, dashboardCardSpan, moveDashboardCard, resolveDashboardCardOrder
} from '../utils/DashboardUtils';
import { feedbackService } from '../services/FeedbackService';
import { publicNetworkService } from '../services/LocalNetworkService';
import { vpnService } from '../services/VpnService';
import { profileStore } from '../stores/ProfileStore';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';
import { ResponsiveMetrics, ResponsiveSizeClass } from '../model/ResponsiveModels';
import {
  resolveResponsiveMetrics,
  resolveContentWidth,
  resolveDashboardSpeedCardHeight,
  resolveDashboardTrafficCardHeight
} from '../utils/ResponsiveUtils';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, FLOATING_ACTION_INSET,
  CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE, HEADER_ACTION_SIZE, HEADER_ACTION_ICON_SIZE
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
  @State activeProfile: Profile | undefined = undefined;
  @State runtime: DashboardSnapshot | undefined = undefined;
  @State history: TrafficSample[] = [];
  @State publicIpv4: string = '未知';
  @State publicCountry: string = '未知地区';
  @State publicNetworkChecking: boolean = true;
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
  @State cardOrder: DashboardCard[] = resolveDashboardCardOrder(settingsStore.getDashboardCardOrder(), true);
  @State editingLayout: boolean = false;
  @State savingLayout: boolean = false;
  @State draggingCard: DashboardCard | undefined = undefined;
  private unsubscribeNetwork: (() => void) | undefined = undefined;
  private unsubscribeLifecycle: (() => void) | undefined = undefined;
  private unsubscribeSettings: (() => void) | undefined = undefined;
  private unsubscribeProfile: (() => void) | undefined = undefined;
  private viewSyncTimer: number | undefined = undefined;
  private lastTrafficSampleTimestamp: number = 0;

  aboutToAppear(): void {
    this.unsubscribeProfile = profileStore.subscribe((snapshot: ProfileStoreSnapshot): void => {
      this.activeProfile = snapshot.profiles.find((profile: Profile): boolean => profile.id === snapshot.activeProfileId);
      this.profileBusy = snapshot.busyProfileId.length > 0;
    });
    this.unsubscribeSettings = settingsStore.subscribe((_snapshot: SettingsStoreSnapshot): void => {
      if (!this.editingLayout && !this.savingLayout) {
        this.syncSavedCardOrder();
      }
    });
    this.unsubscribeLifecycle = vpnService.subscribeLifecycle((snapshot: RuntimeLifecycleSnapshot): void => {
      this.applyLifecycle(snapshot);
    });
    this.unsubscribeNetwork = publicNetworkService.subscribe((snapshot: PublicNetworkSnapshot): void => {
      this.applyPublicNetworkSnapshot(snapshot);
    });
    this.syncViewState();
    this.viewSyncTimer = setInterval((): void => this.syncViewState(), VIEW_SYNC_INTERVAL_MS);
    runtimeStore.refresh();
  }

  aboutToDisappear(): void {
    this.unsubscribeProfile?.();
    this.unsubscribeProfile = undefined;
    this.unsubscribeSettings?.();
    this.unsubscribeSettings = undefined;
    this.unsubscribeLifecycle?.();
    this.unsubscribeLifecycle = undefined;
    this.unsubscribeNetwork?.();
    this.unsubscribeNetwork = undefined;
    if (this.viewSyncTimer !== undefined) {
      clearInterval(this.viewSyncTimer);
      this.viewSyncTimer = undefined;
    }
  }

  private syncViewState(): void {
    const lifecycle = vpnService.getLifecycleSnapshot();
    this.applyLifecycle(lifecycle);
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
    this.publicNetworkChecking = snapshot.checking;
    this.publicNetworkError = snapshot.errorMessage;
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
    const metrics = resolveResponsiveMetrics(resolveContentWidth(width));
    const sizeClassChanged = metrics.sizeClass !== this.metrics.sizeClass;
    this.metrics = metrics;
    if (sizeClassChanged && !this.editingLayout && !this.savingLayout) {
      this.syncSavedCardOrder();
    }
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

  private gridLayoutOptions(): GridLayoutOptions {
    return {
      regularSize: [1, 1],
      irregularIndexes: this.cardOrder.map((_card: DashboardCard, index: number): number => index),
      onGetIrregularSizeByIndex: (index: number): [number, number] => dashboardCardSpan(this.cardOrder[index])
    };
  }

  private moveCard(card: DashboardCard, to: number): void {
    if (this.editingLayout && !this.savingLayout) {
      this.cardOrder = moveDashboardCard(this.cardOrder, this.cardOrder.indexOf(card), to);
    }
  }

  private syncSavedCardOrder(): void {
    this.cardOrder = resolveDashboardCardOrder(settingsStore.getDashboardCardOrder(),
      this.metrics.sizeClass === ResponsiveSizeClass.COMPACT);
  }

  private cardMoveActions(card: DashboardCard): MenuElement[] {
    const index = this.cardOrder.indexOf(card);
    return [
      { value: '前移', enabled: index > 0, action: (): void => { this.moveCard(card, index - 1); } },
      { value: '后移', enabled: index < this.cardOrder.length - 1,
        action: (): void => { this.moveCard(card, index + 1); } }
    ];
  }

  private async toggleLayoutEditing(): Promise<void> {
    if (this.savingLayout || this.draggingCard !== undefined) {
      return;
    }
    this.savingLayout = true;
    try {
      if (!this.editingLayout) {
        const context = this.getUIContext().getHostContext()?.getApplicationContext();
        if (context === undefined) {
          throw new Error('页面尚未就绪，请重试');
        }
        await settingsStore.initialize(context);
        this.syncSavedCardOrder();
        this.editingLayout = true;
      } else {
        await settingsStore.saveDashboardCardOrder(this.cardOrder);
        this.editingLayout = false;
        feedbackService.success('概览布局已保存');
      }
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    } finally {
      this.savingLayout = false;
    }
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
    AlertDialog.show({
      title: '重启 Core',
      message: '重启会短暂中断代理，完成后自动恢复。本次使用时长将继续累计。',
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
      .width(HEADER_ACTION_SIZE).height(HEADER_ACTION_SIZE).padding(0).borderRadius(8)
      .responseRegion({ x: -8, y: -8, width: CONTROL_HEIGHT, height: CONTROL_HEIGHT })
      .backgroundColor($r('app.color.surface_muted'))
      .enabled(!this.isCoreBusy() && !this.isProxyBusy() && !this.profileBusy)
      .accessibilityText(`${this.coreStatus()}，点击重启 Core`)
      .onClick((): void => { this.confirmCoreRestart(); })
      Button({ type: ButtonType.Normal }) {
        if (this.savingLayout) {
          LoadingProgress().width(HEADER_ACTION_ICON_SIZE).height(HEADER_ACTION_ICON_SIZE)
            .color($r('app.color.content_primary'))
        } else {
          Image(this.editingLayout ? $r('app.media.action_check') : $r('app.media.action_edit'))
            .width(HEADER_ACTION_ICON_SIZE).height(HEADER_ACTION_ICON_SIZE)
            .fillColor($r('app.color.content_primary')).accessibilityLevel('no')
        }
      }
      .id('dashboard-layout-edit')
      .width(HEADER_ACTION_SIZE).height(HEADER_ACTION_SIZE).padding(0).borderRadius(8)
      .responseRegion({ x: -8, y: -8, width: CONTROL_HEIGHT, height: CONTROL_HEIGHT })
      .backgroundColor($r('app.color.surface_muted'))
      .enabled(!this.savingLayout && this.draggingCard === undefined)
      .accessibilityText(this.editingLayout ? '保存概览布局' : '编辑概览布局')
      .onClick((): void => { this.toggleLayoutEditing(); })
    }
  }

  @Builder
  private modeCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image($r('app.media.nav_proxy'))
          .width(16).height(16).fillColor($r('app.color.content_secondary'))
          .accessibilityLevel('no')
        Text('出站模式').fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_secondary'))
      }
      .width('100%').height(20)
      .padding({ left: 12, right: 12 })
      ForEach(MODES, (mode: RuntimeMode) => {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 10 }) {
            Image(mode === RuntimeMode.RULE ? $r('app.media.nav_requests') :
              (mode === RuntimeMode.GLOBAL ? $r('app.media.public_network') : $r('app.media.action_check')))
              .width(16).height(16).fillColor($r('app.color.content_secondary'))
              .padding(mode === RuntimeMode.DIRECT ? 2 : 0)
              .border({ width: mode === RuntimeMode.DIRECT ? 1 : 0, color: $r('app.color.content_secondary') })
              .borderRadius(8)
              .accessibilityLevel('no')
            Text(this.modeLabel(mode)).fontSize(BODY_FONT_SIZE)
              .fontColor(this.selectedMode === mode ? $r('app.color.content_primary') : $r('app.color.content_secondary'))
              .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .width('100%')
        }
        .width('100%').height(CONTROL_HEIGHT)
        .padding({ left: 12, right: 12 })
        .borderRadius(18)
        .backgroundColor(this.selectedMode === mode ? $r('app.color.surface_muted') : Color.Transparent)
        .enabled(this.coreState === CoreServiceState.RUNNING && !this.profileBusy &&
          !this.isCoreBusy() && !this.isProxyBusy() && this.runtimeBusyKey.length === 0)
        .accessibilityText(`出站模式：${this.modeLabel(mode)}`)
        .accessibilitySelected(this.selectedMode === mode)
        .onClick((): void => { this.setMode(mode); })
      }, (mode: RuntimeMode): string => mode)
    }
    .width('100%')
    .height(resolveDashboardSpeedCardHeight(this.metrics))
    .alignItems(HorizontalAlign.Start)
    .padding(8)
    .borderRadius(28)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private proxyFloatingButton() {
    Button({ type: ButtonType.Normal }) {
      if (this.isProxyBusy()) {
        LoadingProgress().width(24).height(24).color($r('app.color.vpn_fab_foreground'))
      } else {
        Image(this.isProxyActive() ? $r('app.media.ic_public_pause') : $r('app.media.ic_public_play'))
          .width(24).height(24).fillColor($r('app.color.vpn_fab_foreground'))
      }
    }
    .width(56).height(56).padding(0)
    .borderRadius(28)
    .backgroundColor($r('app.color.vpn_fab_background'))
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
    .enabled(!this.isProxyBusy() && !this.isCoreBusy() && !this.profileBusy && (this.isProxyActive() ||
      (this.coreState === CoreServiceState.RUNNING && this.runtimeProfileId.length > 0 &&
        this.runtimeProfileId === this.activeProfile?.id)))
    .accessibilityText(this.isProxyBusy() ? '正在切换 VPN 代理' : (this.isProxyActive() ? '关闭 VPN 代理' : '开启 VPN 代理'))
    .onClick((): void => { this.toggleProxy(!this.isProxyActive()); })
    .margin({ right: this.metrics.pagePadding, bottom: FLOATING_NAVIGATION_INSET - 16 })
  }

  @Builder
  private configurationCard() {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Image($r('app.media.nav_configuration'))
            .width(16).height(16).fillColor($r('app.color.content_secondary'))
            .accessibilityLevel('no')
          Text('配置').fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_secondary')).layoutWeight(1)
          if (!this.editingLayout) {
            Column() {
              Image($r('app.media.action_chevron_down')).width(12).height(8)
                .fillColor($r('app.color.content_secondary')).rotate({ angle: 180 })
              Image($r('app.media.action_chevron_down')).width(12).height(8)
                .fillColor($r('app.color.content_secondary'))
            }
            .width(24).height(24).borderRadius(12)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.surface_muted'))
            .accessibilityLevel('no')
          }
        }
        .width('100%')
        Row({ space: 8 }) {
          Text(this.activeProfile?.name ?? '选择配置')
            .fontSize(BODY_FONT_SIZE).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary'))
            .layoutWeight(1).textAlign(TextAlign.Start)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.activeProfile !== undefined && (this.activeProfile.totalBytes ?? 0) > 0) {
            Text(`${Math.round(profileUsageRatio(this.activeProfile) * 100)}%`)
              .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
              .flexShrink(0)
          }
        }
        .width('100%')
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(this.metrics.dashboardCardHeight)
    .padding(16)
    .borderRadius(28)
    .backgroundColor($r('app.color.card_background'))
    .accessibilityText(`当前配置：${this.activeProfile?.name ?? '未选择'}，打开配置页`)
    .accessibilityDescription(this.activeProfile !== undefined && (this.activeProfile.totalBytes ?? 0) > 0 ?
      `订阅流量已用 ${Math.round(profileUsageRatio(this.activeProfile) * 100)}%` : '')
    .onClick((): void => { navigationIntentService.publish(AppPage.CONFIGURATION); })
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
      RuntimeSpeedCard({
        runtime: this.runtime, history: this.history,
        proxyState: this.proxyState, coreState: this.coreState,
        cardHeight: this.metrics.sizeClass === ResponsiveSizeClass.COMPACT ? 176 :
          resolveDashboardSpeedCardHeight(this.metrics)
      })
    } else if (card === DashboardCard.TRAFFIC) {
      RuntimeTrafficCard({ runtime: this.runtime, cardHeight: resolveDashboardTrafficCardHeight(this.metrics) })
    } else if (card === DashboardCard.DURATION) {
      RuntimeDurationCard({
        elapsedSeconds: this.elapsedSeconds, hasSession: this.sessionStartedAt > 0,
        cardHeight: this.metrics.dashboardInfoCardHeight
      })
    } else if (card === DashboardCard.CONNECTIONS) {
      RuntimeStatusCard({ runtime: this.runtime, cardHeight: this.metrics.dashboardInfoCardHeight })
    } else if (card === DashboardCard.MEMORY) {
      RuntimeMemoryCard({ runtime: this.runtime, cardHeight: this.metrics.dashboardInfoCardHeight })
    }
  }

  @Builder
  private editableCard(card: DashboardCard) {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() { this.cardContent(card) }
        .width('100%')
        .hitTestBehavior(this.editingLayout ? HitTestMode.None : HitTestMode.Default)
        .accessibilityLevel(this.editingLayout ? 'no-hide-descendants' : 'auto')
      if (this.editingLayout) {
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.action_drag')).width(18).height(18)
            .fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
        }
        .id(`dashboard-card-menu-${card}`)
        .width(28).height(28).padding(0).borderRadius(8).margin(8)
        .responseRegion({ x: -8, y: -8, width: 44, height: 44 })
        .backgroundColor($r('app.color.surface_muted'))
        .enabled(!this.savingLayout && this.draggingCard === undefined)
        .accessibilityText(`移动${dashboardCardLabel(card)}，当前位置 ${this.cardOrder.indexOf(card) + 1}`)
        .bindMenu(this.cardMoveActions(card))
      }
    }
    .width('100%')
    .opacity(this.draggingCard === card ? 0.45 : 1)
    .accessibilityDescription(this.editingLayout ? '长按拖动卡片，或点击移动菜单调整顺序' : '')
  }

  @Builder
  private publicNetworkCard() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Image($r('app.media.public_network'))
          .width(16).height(16).fillColor($r('app.color.content_secondary'))
          .accessibilityLevel('no')
        Text('公网出口')
          .fontSize(CAPTION_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
        if (!this.editingLayout) {
          Button({ type: ButtonType.Normal }) {
            if (this.publicNetworkChecking) {
              LoadingProgress().width(16).height(16).color($r('app.color.nav_selected'))
            } else {
              Image($r('app.media.action_refresh'))
                .width(16).height(16).fillColor($r('app.color.nav_selected'))
            }
          }
          .width(24).height(24).padding(0).borderRadius(BUTTON_RADIUS)
          .responseRegion({ x: -12, y: -12, width: CONTROL_HEIGHT, height: CONTROL_HEIGHT })
          .backgroundColor(Color.Transparent)
          .enabled(!this.publicNetworkChecking)
          .accessibilityText('刷新公网出口')
          .onClick((): void => { publicNetworkService.refresh(); })
        }
      }
      .width('100%')
      Column({ space: 2 }) {
        Text(this.publicIpv4 === '未知' ? '—' : this.publicIpv4)
          .fontSize(BODY_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
          .wordBreak(WordBreak.BREAK_ALL)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.publicNetworkDetail())
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor(this.publicNetworkError.length > 0 ? $r('app.color.status_error') : $r('app.color.content_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
    }
    .width('100%')
    .constraintSize({ minHeight: this.metrics.dashboardCardHeight })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.SpaceBetween)
    .padding(12)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: this.metrics.sectionGap }) {
        PageHeader({
          title: $r('app.string.nav_dashboard'), contentPadding: this.metrics.pagePadding,
          subtitle: this.editingLayout ? '长按拖动卡片，点击右上角保存' : this.headerHint(),
          subtitleColor: !this.editingLayout && this.hasStatusError() ?
            $r('app.color.status_error') : $r('app.color.content_secondary'),
          actions: (): void => { this.headerActions(); }
        })
        Grid(undefined, this.gridLayoutOptions()) {
          ForEach(this.cardOrder, (card: DashboardCard) => {
            GridItem() { this.editableCard(card) }
              .id(`dashboard-card-${card}`)
              .draggable(this.editingLayout && !this.savingLayout)
              .onDragStart((event: DragEvent): DragItemInfo => {
                if (!this.editingLayout || this.savingLayout) {
                  event.setResult(DragResult.DRAG_CANCELED);
                  return {};
                }
                this.draggingCard = card;
                return {};
              })
              .onDrop((): void => {
                if (this.draggingCard !== undefined) {
                  this.moveCard(this.draggingCard, this.cardOrder.indexOf(card));
                }
              })
              .onDragEnd((): void => { this.draggingCard = undefined; })
          }, (card: DashboardCard): string => card)
        }
        .columnsTemplate(this.metrics.sizeClass === ResponsiveSizeClass.COMPACT ? '1fr 1fr' : '1fr 1fr 1fr 1fr')
        .columnsGap(this.metrics.cardGap)
        .rowsGap(this.metrics.cardGap)
        .cachedCount(8)
        .contentEndOffset(this.metrics.pagePadding + FLOATING_NAVIGATION_INSET + FLOATING_ACTION_INSET)
        .padding({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      .width('100%')
      .height('100%')
      if (!this.editingLayout) {
        this.proxyFloatingButton()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_old: Area, area: Area): void => { this.updateWidth(area.width); })
  }
}
