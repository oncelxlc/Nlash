import { AppSettings, AppThemeMode, NavigationTransition, SettingsStoreSnapshot } from '../model/SettingsModels';
import { NAVIGATION_TRANSITION_OPTIONS, REFRESH_INTERVAL_OPTIONS } from '../constants/SettingsConstants';
import { RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { feedbackService } from '../services/FeedbackService';
import { coreClient } from '../services/CoreClient';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';
import { ResponsiveMetrics, ResponsiveSizeClass } from '../model/ResponsiveModels';
import { resolveResponsiveMetrics, resolveContentWidth } from '../utils/ResponsiveUtils';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE
} from '../constants/UiConstants';

import { PageHeader } from '../components/PageHeader';
import { SingleChoiceControl } from '../components/SingleChoiceControl';

const THEMES: AppThemeMode[] = [AppThemeMode.SYSTEM, AppThemeMode.LIGHT, AppThemeMode.DARK];

@Component
export struct SettingsPage {
  @State settings: AppSettings = settingsStore.getSnapshot().settings;
  @State saving: boolean = false;
  @State networkError: string = '';
  @State mtuInput: string = '1400';
  @State delayUrlInput: string = '';
  @State runtimeAvailable: boolean = false;
  @State runtimeBusyKey: string = '';
  @State coreVersion: string = '--';
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  @State pageWidth: number = 0;
  private sections: WaterFlowSections = new WaterFlowSections();
  private unsubscribeSettings: (() => void) | undefined = undefined;
  private unsubscribeRuntime: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.updateSections();
    this.unsubscribeSettings = settingsStore.subscribe((snapshot: SettingsStoreSnapshot): void => {
      this.settings = snapshot.settings;
      this.saving = snapshot.saving;
      if (!snapshot.saving) {
        this.mtuInput = snapshot.settings.mtu.toString();
        this.delayUrlInput = snapshot.settings.delayTestUrl;
      }
    });
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.runtimeAvailable = snapshot.coreAvailable;
      this.runtimeBusyKey = snapshot.busyKey;
    });
    try {
      this.coreVersion = coreClient.getVersion();
    } catch (error) {
      this.coreVersion = 'Core 不可用';
    }
  }

  aboutToDisappear(): void {
    this.unsubscribeSettings?.();
    this.unsubscribeSettings = undefined;
    this.unsubscribeRuntime?.();
    this.unsubscribeRuntime = undefined;
  }

  private updateWidth(width: Length): void {
    this.pageWidth = resolveContentWidth(width);
    const next = resolveResponsiveMetrics(this.pageWidth);
    if (next.sizeClass !== this.metrics.sizeClass) {
      this.metrics = next;
      this.updateSections();
    }
  }

  private settingsCardWidth(): Length {
    if (this.pageWidth <= 0) {
      return '100%';
    }
    const columns = this.metrics.sizeClass === ResponsiveSizeClass.COMPACT ? 1 : 2;
    // Percentage children of a section resolve against the full WaterFlow width.
    return (this.pageWidth - this.metrics.pagePadding * 2 - (columns - 1) * 12) / columns;
  }

  private updateSections(): void {
    this.sections.splice(0, this.sections.length(), [
      { itemsCount: 1, crossCount: 1, margin: { bottom: 16 } },
      { itemsCount: 4, crossCount: this.metrics.sizeClass === ResponsiveSizeClass.COMPACT ? 1 : 2,
        columnsGap: 12, rowsGap: 12 },
      { itemsCount: 1, crossCount: 1, margin: { top: 16 } }
    ]);
  }

  private themeLabel(theme: AppThemeMode): string {
    if (theme === AppThemeMode.LIGHT) {
      return '浅色';
    }
    if (theme === AppThemeMode.DARK) {
      return '深色';
    }
    return '跟随系统';
  }

  private async saveNetworkSettings(): Promise<void> {
    this.networkError = '';
    try {
      await settingsStore.setNetworkSettings(Number(this.mtuInput), this.delayUrlInput);
      feedbackService.success('网络设置已保存');
    } catch (error) {
      this.networkError = this.errorMessage(error);
      feedbackService.error(this.networkError);
    }
  }

  private async changeTheme(theme: AppThemeMode): Promise<void> {
    try {
      await settingsStore.setThemeMode(theme);
      feedbackService.success('主题设置已保存');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async changeRefreshInterval(seconds: number): Promise<void> {
    try {
      await settingsStore.setRefreshIntervalSeconds(seconds);
      feedbackService.success(`数据刷新间隔已设为 ${seconds} 秒`);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private transitionLabel(transition: NavigationTransition): string {
    switch (transition) {
      case NavigationTransition.NONE: return '关闭';
      case NavigationTransition.FADE: return '淡入';
      case NavigationTransition.SLIDE: return '平移';
    }
  }

  private async changeNavigationTransition(transition: NavigationTransition): Promise<void> {
    try {
      await settingsStore.setNavigationTransition(transition);
      feedbackService.success('导航切换效果已保存');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : '设置操作失败';
  }

  private async resetTraffic(): Promise<void> {
    try {
      await runtimeStore.resetTraffic();
      feedbackService.success('流量统计已重置');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private clearRequests(): void {
    runtimeStore.clearRequests();
    feedbackService.success('请求记录已清空');
  }

  @Builder
  private sectionTitle(title: string, subtitle: string) {
    Column({ space: 6 }) {
      Text(title).fontSize(18).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary')).width('100%')
      Text(subtitle).fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary')).width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private themeCard() {
    Column({ space: 16 }) {
      this.sectionTitle('外观', '选择适合当前环境的配色')
      SingleChoiceControl({
        labels: THEMES.map((theme: AppThemeMode): string => this.themeLabel(theme)),
        selectedIndex: THEMES.indexOf(this.settings.themeMode),
        isEnabled: !this.saving,
        accessibilityLabel: '应用配色',
        onChange: (index: number): void => { this.changeTheme(THEMES[index]); }
      })
      Text('导航切换效果').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary')).width('100%')
      SingleChoiceControl({
        labels: NAVIGATION_TRANSITION_OPTIONS.map((transition: NavigationTransition): string =>
          this.transitionLabel(transition)),
        selectedIndex: NAVIGATION_TRANSITION_OPTIONS.indexOf(this.settings.navigationTransition),
        isEnabled: !this.saving,
        accessibilityLabel: '导航切换效果',
        onChange: (index: number): void => { this.changeNavigationTransition(NAVIGATION_TRANSITION_OPTIONS[index]); }
      })
    }
    .width(this.settingsCardWidth()).padding(16)
    .borderRadius(CARD_RADIUS).backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private networkCard() {
    Column({ space: 12 }) {
      this.sectionTitle('网络', '配置 VPN 与节点延迟测试')
      Text('VPN MTU').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary')).width('100%')
      TextInput({ placeholder: '1280–9000', text: this.mtuInput })
        .type(InputType.Number).height(CONTROL_HEIGHT).width('100%').fontSize(BODY_FONT_SIZE)
        .fontColor($r('app.color.content_primary')).placeholderColor($r('app.color.content_secondary'))
        .backgroundColor($r('app.color.app_background'))
        .border({ width: 1, color: $r('app.color.control_border') }).borderRadius(BUTTON_RADIUS)
        .enabled(!this.saving).accessibilityText('VPN MTU，1280 至 9000')
        .onChange((value: string): void => { this.mtuInput = value; })
      Text('延迟测试地址 · HTTP(S)').fontSize(14).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary')).width('100%')
      TextInput({ placeholder: 'https://', text: this.delayUrlInput })
        .type(InputType.URL).height(CONTROL_HEIGHT).width('100%').fontSize(BODY_FONT_SIZE)
        .fontColor($r('app.color.content_primary')).placeholderColor($r('app.color.content_secondary'))
        .backgroundColor($r('app.color.app_background'))
        .border({ width: 1, color: $r('app.color.control_border') }).borderRadius(BUTTON_RADIUS)
        .enabled(!this.saving).accessibilityText('延迟测试 HTTP 或 HTTPS 地址')
        .onChange((value: string): void => { this.delayUrlInput = value; })
      if (this.networkError.length > 0) {
        Text(this.networkError).fontSize(14).fontColor($r('app.color.status_error')).width('100%')
      }
      Button(this.saving ? '保存中…' : '保存网络设置')
        .type(ButtonType.Normal).constraintSize({ minHeight: CONTROL_HEIGHT }).width('100%').borderRadius(BUTTON_RADIUS)
        .fontSize(BODY_FONT_SIZE).fontColor($r('app.color.accent_foreground')).backgroundColor($r('app.color.action_primary'))
        .enabled(!this.saving)
        .onClick((): void => { this.saveNetworkSettings(); })
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.settingsCardWidth()).padding(16)
    .borderRadius(CARD_RADIUS).backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private dataCard() {
    Column({ space: 16 }) {
      this.sectionTitle('运行数据', '速度、连接与节点信息的刷新间隔')
      SingleChoiceControl({
        labels: REFRESH_INTERVAL_OPTIONS.map((seconds: number): string => `${seconds} 秒`),
        selectedIndex: REFRESH_INTERVAL_OPTIONS.indexOf(this.settings.refreshIntervalSeconds),
        isEnabled: !this.saving,
        accessibilityLabel: '运行数据刷新间隔',
        onChange: (index: number): void => { this.changeRefreshInterval(REFRESH_INTERVAL_OPTIONS[index]); }
      })
    }
    .width(this.settingsCardWidth()).padding(16)
    .borderRadius(CARD_RADIUS).backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private cleanupCard() {
    Column({ space: 12 }) {
      this.sectionTitle('数据管理', '管理当前累计统计和会话记录')
      Button(this.runtimeBusyKey.length > 0 ? '处理中…' : '重置 Core 流量统计')
        .type(ButtonType.Normal).constraintSize({ minHeight: CONTROL_HEIGHT }).width('100%').borderRadius(BUTTON_RADIUS)
        .fontSize(14).fontColor($r('app.color.status_error')).backgroundColor($r('app.color.status_error_surface'))
        .enabled(this.runtimeAvailable && this.runtimeBusyKey.length === 0)
        .onClick((): void => { this.resetTraffic(); })
      Button('清空会话请求记录')
        .type(ButtonType.Normal).constraintSize({ minHeight: CONTROL_HEIGHT }).width('100%').borderRadius(BUTTON_RADIUS)
        .fontSize(14).fontColor($r('app.color.status_error')).backgroundColor($r('app.color.status_error_surface'))
        .onClick((): void => { this.clearRequests(); })
    }
    .width(this.settingsCardWidth()).padding(16)
    .borderRadius(CARD_RADIUS).backgroundColor($r('app.color.card_background'))
  }

  build() {
    WaterFlow({ sections: this.sections }) {
      FlowItem() {
        PageHeader({ title: $r('app.string.nav_settings'), subtitle: '按你的习惯调整 Nlash' })
      }
      FlowItem() { this.themeCard() }
      FlowItem() { this.networkCard() }
      FlowItem() { this.dataCard() }
      FlowItem() { this.cleanupCard() }
      FlowItem() {
        Column({ space: 12 }) {
          this.sectionTitle('关于 Nlash', `1.0.0 · ${this.coreVersion}`)
          Divider().color($r('app.color.nav_divider'))
          Text('Mihomo v1.19.30')
            .fontSize(BODY_FONT_SIZE).fontColor($r('app.color.content_primary')).width('100%')
          Text('配置与订阅保存在应用沙箱中。')
            .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary')).width('100%')
        }
        .alignItems(HorizontalAlign.Start).width('100%').padding(16)
        .borderRadius(CARD_RADIUS).backgroundColor($r('app.color.card_background'))
      }
    }
    .cachedCount(6)
    .contentEndOffset(this.metrics.pagePadding + FLOATING_NAVIGATION_INSET)
    .padding({
      top: this.metrics.pagePadding, left: this.metrics.pagePadding, right: this.metrics.pagePadding
    })
    .width('100%').height('100%')
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onAreaChange((_old: Area, area: Area): void => { this.updateWidth(area.width); })
  }
}
