import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveResponsiveMetrics, resolveContentWidth } from '../utils/ResponsiveUtils';
import { FLOATING_NAVIGATION_INSET } from '../constants/UiConstants';

import { PageHeader } from '../components/PageHeader';
import { FadingScrollLayout } from '../components/FadingScrollLayout';
import { AppPage } from '../model/NavigationModels';
import { RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { generalSettingsService } from '../services/GeneralSettingsService';
import { coreClient } from '../services/CoreClient';
import { runtimeStore } from '../stores/RuntimeStore';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 设置入口；网络选项由常规页维护。 */
@Component
export struct SettingsPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @StorageProp('logCaptureEnabled') logCaptureEnabled: boolean = false;
  @Prop @Watch('updateActivity') isActive: boolean = true;
  @State headerInset: number = 0;
  onOpenPage: (page: AppPage) => void = (): void => {};
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribeRuntime: (() => void) | undefined;

  aboutToAppear(): void { this.updateActivity(); }
  aboutToDisappear(): void { this.unsubscribeRuntime?.(); this.unsubscribeRuntime = undefined; }

  private updateActivity(): void {
    this.unsubscribeRuntime?.();
    this.unsubscribeRuntime = undefined;
    if (!this.isActive) { return; }
    let available: boolean | undefined;
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      if (available === snapshot.coreAvailable) { return; }
      available = snapshot.coreAvailable;
      this.loadLogCapture();
    });
  }

  private async loadLogCapture(): Promise<void> {
    try {
      if (coreClient.getVersion() !== 'unavailable/non-arm64') { await generalSettingsService.load(); }
    } catch (_error) {
      hilog.warn(0x4E4C, 'NlashSettings', 'Cannot refresh log capture setting');
    }
  }

  @Builder
  private themeCard() {
    Column() {
      this.moreRow('常规', $r('app.media.nav_settings'), AppPage.GENERAL)
      this.moreRow('主题', $r('app.media.theme_palette'), AppPage.THEME, false)
      if (this.logCaptureEnabled) {
        Divider().color(this.theme.divider).width('100%').padding({ left: 64, right: 20 })
        this.moreRow('日志', $r('app.media.nav_requests'), AppPage.LOGS, false)
      }
    }
    .width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
  }

  @Builder
  private moreRow(title: string, icon: Resource, page: AppPage, divider: boolean = true) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 20 }) {
        Image(icon).width(24).height(24).fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
        Text(title).fontSize(themeFontSize(18, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_primary')).layoutWeight(1).textAlign(TextAlign.Start)
        Image($r('app.media.action_chevron_down')).width(18).height(18)
          .fillColor($r('app.color.content_secondary')).rotate({ angle: -90 }).accessibilityLevel('no')
      }.width('100%')
    }
    .id(`settings-more-${page}`)
    .width('100%').constraintSize({ minHeight: 64 }).padding({ left: 20, right: 20, top: 16, bottom: 16 })
    .borderRadius(0).backgroundColor(Color.Transparent).accessibilityText(title)
    .onClick((): void => { this.onOpenPage(page); })
    if (divider) {
      Divider().color(this.theme.divider).width('100%').padding({ left: 64, right: 20 })
    }
  }

  @Builder
  private moreCard() {
    Column({ space: 12 }) {
      Text('更多').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
        .width('100%').padding({ left: 16 })
      Column() {
        this.moreRow('最近请求', $r('app.media.runtime_duration'), AppPage.REQUESTS)
        this.moreRow('实时连接', $r('app.media.nav_connections'), AppPage.CONNECTIONS)
        this.moreRow('DNS 查询', $r('app.media.nav_dns'), AppPage.DNS)
        this.moreRow('资源', $r('app.media.nav_resources'), AppPage.RESOURCES, false)
      }
      .width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
    }.width('100%')
  }

  @Builder
  private scrollContent() {
    Scroll() {
      Column({ space: 16 }) {
        this.themeCard()
        this.moreCard()
        Column() { this.moreRow('关于', $r('app.media.nav_resources'), AppPage.ABOUT, false) }
          .width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
      }.width('100%').padding({ top: this.headerInset,
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET,
        left: this.metrics.pagePadding, right: this.metrics.pagePadding })
    }
    .scrollBar(BarState.Off)
    .width('100%').height('100%')
    .align(Alignment.Top)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private pageHeader() {
    PageHeader({ title: $r('app.string.nav_settings'), contentPadding: this.metrics.pagePadding })
  }

  build() {
    FadingScrollLayout({
      topInset: $headerInset,
      header: (): void => { this.pageHeader(); },
      content: (): void => { this.scrollContent(); }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .onAreaChange((_old: Area, area: Area): void => {
      this.metrics = resolveResponsiveMetrics(resolveContentWidth(area.width));
    })
  }
}
