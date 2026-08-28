import { AppSettings, AppThemeMode, SettingsStoreSnapshot } from '../models/SettingsModels';
import { RuntimeStoreSnapshot } from '../models/RuntimeModels';
import { feedbackService } from '../services/FeedbackService';
import { coreClient } from '../services/CoreClient';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';
import { ResponsiveMetrics, resolveResponsiveMetrics } from '../ui/ResponsiveMetrics';
import { BUTTON_RADIUS } from '../ui/UiConstants';

const THEMES: AppThemeMode[] = [AppThemeMode.SYSTEM, AppThemeMode.LIGHT, AppThemeMode.DARK];

@Component
export struct SettingsPage {
  @State settings: AppSettings = settingsStore.getSnapshot().settings;
  @State saving: boolean = false;
  @State mtuInput: string = '1400';
  @State delayUrlInput: string = '';
  @State runtimeAvailable: boolean = false;
  @State runtimeBusyKey: string = '';
  @State coreVersion: string = '--';
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribeSettings: (() => void) | undefined = undefined;
  private unsubscribeRuntime: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribeSettings = settingsStore.subscribe((snapshot: SettingsStoreSnapshot): void => {
      this.settings = snapshot.settings;
      this.saving = snapshot.saving;
      if (!snapshot.saving) {
        this.mtuInput = snapshot.settings.mtu.toString();
        this.delayUrlInput = snapshot.settings.delayTestUrl;
      }
    });
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.runtimeAvailable = snapshot.available;
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
    const numericWidth = typeof width === 'number' ? width : (typeof width === 'string' ? Number(width) : 0);
    this.metrics = resolveResponsiveMetrics(Number.isFinite(numericWidth) ? numericWidth : 0);
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
    try {
      await settingsStore.setNetworkSettings(Number(this.mtuInput), this.delayUrlInput);
      feedbackService.success('网络设置已保存');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
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
  private cardHeader(title: string, subtitle: string) {
    Column({ space: 3 }) {
      Text(title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
        .width('100%')
      Text(subtitle)
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
  }

  @Builder
  private themeCard() {
    Column({ space: 14 }) {
      this.cardHeader('主题', '选择跟随系统、浅色或深色。')
      this.themeContent()
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.metrics.dashboardCardWidth)
    .padding(18)
    .margin({ bottom: this.metrics.cardGap })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private networkCard() {
    Column({ space: 14 }) {
      this.cardHeader('网络', 'MTU 范围 1280–9000；延迟测试只接受 HTTP(S)。')
      this.networkContent()
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.metrics.dashboardCardWidth)
    .padding(18)
    .margin({ bottom: this.metrics.cardGap })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private dataCard() {
    Column({ space: 14 }) {
      this.cardHeader('运行数据', '这些操作只影响当前 Core 会话和本地请求历史。')
      this.dataContent()
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.metrics.dashboardCardWidth)
    .padding(18)
    .margin({ bottom: this.metrics.cardGap })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private themeContent() {
    Row({ space: 8 }) {
      ForEach(THEMES, (theme: AppThemeMode) => {
        Button(this.themeLabel(theme))
          .type(ButtonType.Normal)
          .borderRadius(BUTTON_RADIUS)
          .layoutWeight(1)
          .fontColor(this.settings.themeMode === theme ? Color.White : $r('app.color.content_primary'))
          .backgroundColor(this.settings.themeMode === theme ?
            $r('app.color.nav_selected') : $r('app.color.app_background'))
          .enabled(!this.saving)
          .onClick((): void => {
            this.changeTheme(theme);
          })
      }, (theme: AppThemeMode): string => theme)
    }
    .width('100%')
  }

  @Builder
  private networkContent() {
    Column({ space: 10 }) {
      TextInput({ placeholder: 'VPN MTU', text: this.mtuInput })
        .type(InputType.Number)
        .height(46)
        .onChange((value: string): void => {
          this.mtuInput = value;
        })
      TextInput({ placeholder: '延迟测试 HTTP(S) 地址', text: this.delayUrlInput })
        .type(InputType.URL)
        .height(46)
        .onChange((value: string): void => {
          this.delayUrlInput = value;
        })
      Button('保存网络设置')
        .type(ButtonType.Normal)
        .borderRadius(BUTTON_RADIUS)
        .width('100%')
        .enabled(!this.saving)
        .onClick((): void => {
          this.saveNetworkSettings();
        })
    }
    .width('100%')
  }

  @Builder
  private dataContent() {
    Column({ space: 8 }) {
      Button('重置 Core 流量统计')
        .type(ButtonType.Normal)
        .borderRadius(BUTTON_RADIUS)
        .width('100%')
        .enabled(this.runtimeAvailable && this.runtimeBusyKey.length === 0)
        .onClick((): void => {
          this.resetTraffic();
        })
      Button('清空会话请求记录')
        .type(ButtonType.Normal)
        .borderRadius(BUTTON_RADIUS)
        .width('100%')
        .onClick((): void => {
          this.clearRequests();
        })
    }
    .width('100%')
  }

  build() {
    Scroll() {
      Column({ space: this.metrics.sectionGap }) {
        Column({ space: 4 }) {
          Text($r('app.string.nav_settings'))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.content_primary'))
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')

        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
          this.themeCard()
          this.networkCard()
          this.dataCard()
        }
        .width('100%')

        Column({ space: 8 }) {
          Text('关于')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary'))
            .width('100%')
          Text(`Nlash 1.0.0 · ${this.coreVersion}`)
            .fontSize(13)
            .fontColor($r('app.color.content_secondary'))
            .width('100%')
          Text('Core 固定 Mihomo v1.19.30；配置与订阅仅保存在应用沙箱。')
            .fontSize(13)
            .fontColor($r('app.color.content_secondary'))
            .width('100%')
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .padding(18)
        .borderRadius(16)
        .backgroundColor($r('app.color.card_background'))

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
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.updateWidth(newValue.width);
    })
  }
}
