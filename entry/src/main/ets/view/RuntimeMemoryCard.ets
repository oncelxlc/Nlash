import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LengthMetrics } from '@kit.ArkUI';
import { DASHBOARD_CARD_RADIUS, DASHBOARD_CARD_PADDING } from '../constants/DashboardConstants';
import { DashboardSnapshot } from '../model/RuntimeModels';
import { DashboardMemoryUsage } from '../model/DashboardModels';
import { dashboardMemoryUsage, formatMemoryMegabytes } from '../utils/DashboardUtils';
import { readAppMemoryBytes } from '../services/AppMemoryService';

const MEMORY_POLL_INTERVAL_MS = 5000;

/** UI 进程 PSS 与独立宿主的 Mihomo 内存统计分别展示，缺失数据保留占位。 */
@Component
export struct RuntimeMemoryCard {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop runtime: DashboardSnapshot | undefined = undefined;
  @Prop cardHeight: number = 148;
  @State appMemoryBytes: number | undefined = undefined;
  private generation: number = 0;
  private readingMemory: boolean = false;
  private timer: number | undefined = undefined;

  aboutToAppear(): void {
    this.generation += 1;
    this.refreshMemory();
    this.timer = setInterval((): void => { this.refreshMemory(); }, MEMORY_POLL_INTERVAL_MS);
  }

  aboutToDisappear(): void {
    this.generation += 1;
    if (this.timer !== undefined) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
  }

  private async refreshMemory(): Promise<void> {
    if (this.readingMemory) { return; }
    const generation = this.generation;
    this.readingMemory = true;
    try {
      const bytes = await readAppMemoryBytes();
      if (generation === this.generation) { this.appMemoryBytes = bytes; }
    } catch (error) {
      if (generation === this.generation) {
        this.appMemoryBytes = undefined;
        hilog.warn(0xD001, 'RuntimeMemoryCard', 'Cannot read app memory: %{public}s', String(error));
      }
    } finally {
      this.readingMemory = false;
    }
  }

  private usage(): DashboardMemoryUsage {
    return dashboardMemoryUsage(this.appMemoryBytes, this.runtime?.memoryBytes);
  }

  private showDetails(): void {
    AlertDialog.show({
      title: '内存信息',
      message: `应用 ${formatMemoryMegabytes(this.usage().appBytes)} MB\n` +
        `内核 ${formatMemoryMegabytes(this.usage().coreBytes)} MB\n\n` +
        '应用为 UI 进程物理内存（PSS），每 5 秒刷新；内核为 Mihomo 统计值，来自独立 VPN 宿主。' +
        '合计为两项之和，缺失时显示“—”。MB 按 1024 × 1024 字节换算。',
      confirm: { value: '知道了', action: (): void => {} }
    });
  }

  @Builder
  private legend(app: boolean) {
    Row({ space: 6 }) {
      Row().width(8).height(8).borderRadius(4)
        .backgroundColor(app ? this.theme.accent : this.theme.accentSecondary)
        .accessibilityLevel('no')
      Text(app ? '应用' : '内核').fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
      Text(`${formatMemoryMegabytes(app ? this.appMemoryBytes : this.runtime?.memoryBytes)} MB`)
        .fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
    }
    .accessibilityGroup(true)
    .accessibilityText(`${app ? '应用' : '内核'}内存 ${
      formatMemoryMegabytes(app ? this.appMemoryBytes : this.runtime?.memoryBytes)} MB`)
  }

  build() {
    Column({ space: 12 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Image($r('app.media.runtime_memory')).width(18).height(18)
            .fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
          Text('内存信息').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary')).layoutWeight(1).textAlign(TextAlign.Start)
          Image($r('app.media.action_chevron_down')).width(18).height(18).rotate({ angle: -90 })
            .fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
        }
        .width('100%').height(44)
      }
      .id('dashboard-memory-details').width('100%').padding(0).backgroundColor(Color.Transparent).borderRadius(8)
      .margin({ top: -10, bottom: -8 }).accessibilityText('查看内存信息详情')
      .onClick((): void => { this.showDetails(); })
      Text() {
        Span(formatMemoryMegabytes(this.usage().totalBytes)).fontSize(themeFontSize(32, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold)
        Span(' MB').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
      }
      .fontColor($r('app.color.content_primary')).maxLines(2)
      .accessibilityText(`合计内存 ${this.usage().totalBytes === undefined ? '暂不可用' :
        `${formatMemoryMegabytes(this.usage().totalBytes)} MB`}`)
      Column({ space: 10 }) {
        Stack({ alignContent: Alignment.Start }) {
          if ((this.usage().totalBytes ?? 0) > 0) {
            Row() {
              if (this.usage().appRatio > 0) {
                Row().layoutWeight(this.usage().appRatio).height('100%')
                  .backgroundColor(this.theme.accent)
              }
              if (this.usage().appRatio > 0 && this.usage().appRatio < 1) {
                Row().width(2).height('100%').backgroundColor(this.theme.surface)
              }
              if (this.usage().appRatio < 1) {
                Row().layoutWeight(1 - this.usage().appRatio).height('100%')
                  .backgroundColor(this.theme.accentSecondary)
              }
            }
            .width('100%').height('100%')
          }
        }
        .id('dashboard-memory-bar').width('100%').height(8).borderRadius(4).clip(true)
        .backgroundColor(this.theme.muted).accessibilityLevel('no')
        Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(16), cross: LengthMetrics.vp(6) } }) {
          this.legend(true)
          this.legend(false)
        }
        .width('100%')
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start).justifyContent(FlexAlign.SpaceBetween).width('100%')
    .constraintSize({ minHeight: this.cardHeight }).padding(DASHBOARD_CARD_PADDING)
    .borderRadius(DASHBOARD_CARD_RADIUS).backgroundColor(this.theme.surface)
  }
}
