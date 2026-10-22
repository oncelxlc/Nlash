import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveResponsiveMetrics, resolveContentWidth } from '../utils/ResponsiveUtils';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, CARD_RADIUS, CAPTION_FONT_SIZE
} from '../constants/UiConstants';

import { PageHeader } from '../components/PageHeader';
import { FadingScrollLayout } from '../components/FadingScrollLayout';
import { AppPage } from '../model/NavigationModels';

/** 设置入口与运行数据清理；网络选项由常规页维护。 */
@Component
export struct SettingsPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop @Watch('updateActivity') isActive: boolean = true;
  @State headerInset: number = 0;
  onOpenPage: (page: AppPage) => void = (): void => {};
  @State runtimeAvailable: boolean = false;
  @State runtimeBusyKey: string = '';
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribeRuntime: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.updateActivity();
  }

  aboutToDisappear(): void {
    this.unsubscribeRuntime?.();
    this.unsubscribeRuntime = undefined;
  }

  private updateActivity(): void {
    this.unsubscribeRuntime?.();
    this.unsubscribeRuntime = undefined;
    if (this.isActive) {
      this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
        this.runtimeAvailable = snapshot.coreAvailable;
        this.runtimeBusyKey = snapshot.busyKey;
      });
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
  private sectionTitle(title: string, subtitle?: string) {
    Column({ space: 6 }) {
      Text(title).fontSize(themeFontSize(18, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary')).width('100%')
      if (!!subtitle) {
        Text(subtitle).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).width('100%')
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private themeCard() {
    Column() {
      this.moreRow('常规', $r('app.media.nav_settings'), AppPage.GENERAL)
      this.moreRow('主题', $r('app.media.theme_palette'), AppPage.THEME, false)
    }
    .width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
  }

  @Builder
  private cleanupCard() {
    Column({ space: 12 }) {
      this.sectionTitle('数据管理')
      Button(this.runtimeBusyKey.length > 0 ? '处理中…' : '重置 Core 流量统计')
        .type(ButtonType.Normal).constraintSize({ minHeight: CONTROL_HEIGHT }).width('100%').borderRadius(BUTTON_RADIUS)
        .fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.status_error')).backgroundColor($r('app.color.status_error_surface'))
        .enabled(this.runtimeAvailable && this.runtimeBusyKey.length === 0)
        .onClick((): void => { this.resetTraffic(); })
      Button('清空会话请求记录')
        .type(ButtonType.Normal).constraintSize({ minHeight: CONTROL_HEIGHT }).width('100%').borderRadius(BUTTON_RADIUS)
        .fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.status_error')).backgroundColor($r('app.color.status_error_surface'))
        .onClick((): void => { this.clearRequests(); })
    }
    .width('100%').padding(16)
    .borderRadius(CARD_RADIUS).backgroundColor(this.theme.surface)
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
        this.cleanupCard()
        Column() { this.moreRow('关于', $r('app.media.nav_resources'), AppPage.ABOUT, false) }
          .width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
      }.width('100%').padding({ top: this.headerInset,
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET,
        left: this.metrics.pagePadding, right: this.metrics.pagePadding })
    }
    .scrollBar(BarState.Off)
    .width('100%').height('100%')
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
