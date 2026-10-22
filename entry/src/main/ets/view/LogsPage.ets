import { common } from '@kit.AbilityKit';
import { AppTheme } from '../model/ThemeModels';
import { LogLevel, LogRecord } from '../model/LogModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { filterLogs, formatLogTime } from '../utils/LogUtils';
import { resolveContentWidth, resolveResponsiveMetrics } from '../utils/ResponsiveUtils';
import { LOG_LEVELS, LOG_LEVEL_LABELS } from '../constants/LogConstants';
import { CONTROL_HEIGHT } from '../constants/UiConstants';
import { logService } from '../services/LogService';
import { coreClient } from '../services/CoreClient';
import { feedbackService } from '../services/FeedbackService';
import { SecondaryPageHeader } from '../components/SecondaryPageHeader';
import { HeaderIconButton } from '../components/HeaderIconButton';
import { EmptyStateBackground } from '../components/EmptyStateBackground';

class LogDataSource implements IDataSource {
  private records: LogRecord[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.records.length; }
  getData(index: number): LogRecord { return this.records[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((item: DataChangeListener): boolean => item !== listener);
  }
  update(records: LogRecord[]): void {
    this.records = records;
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded(); });
  }
}

@Component
export struct LogsPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @StorageProp('logCaptureEnabled') @Watch('captureChanged') logCaptureEnabled: boolean = false;
  @Prop @Watch('updateActivity') isActive: boolean = true;
  onBack: () => void = (): void => {};
  @State query: string = '';
  @State capture: boolean = false;
  @State level: LogLevel = LogLevel.INFO;
  @State totalCount: number = 0;
  @State matchCount: number = 0;
  @State loaded: boolean = false;
  @State loading: boolean = false;
  @State exporting: boolean = false;
  @State errorMessage: string = '';
  @State contentPadding: number = 16;
  private records: LogRecord[] = [];
  private source: LogDataSource = new LogDataSource();
  private generation: number = 0;
  private timer: number | undefined;

  aboutToAppear(): void { this.updateActivity(); }
  aboutToDisappear(): void { this.stopPolling(); }

  private captureChanged(): void {
    if (this.logCaptureEnabled) { return; }
    this.stopPolling();
    this.capture = false;
    this.records = [];
    this.totalCount = 0;
    this.updateResults();
    if (this.isActive) { this.load(this.generation); }
  }

  private stopPolling(): void {
    this.generation += 1;
    if (this.timer !== undefined) { clearTimeout(this.timer); this.timer = undefined; }
    this.loading = false;
  }

  private updateActivity(): void {
    this.stopPolling();
    if (!this.isActive) { return; }
    try {
      if (coreClient.getVersion() === 'unavailable/non-arm64') {
        this.errorMessage = '当前设备不支持 Mihomo Core，无法捕获内核日志。';
        return;
      }
    } catch (_error) {
      this.errorMessage = '内核不可用，无法读取日志。';
      return;
    }
    this.load(this.generation);
  }

  private async load(generation: number): Promise<void> {
    this.loading = true;
    try {
      const snapshot = await logService.load();
      if (generation !== this.generation) { return; }
      this.capture = snapshot.capture;
      this.level = snapshot.level;
      this.records = snapshot.records;
      this.totalCount = this.records.length;
      this.updateResults();
      this.loaded = true;
      this.errorMessage = '';
    } catch (error) {
      if (generation === this.generation) { this.errorMessage = (error as Error).message || '读取日志失败'; }
    } finally {
      if (generation === this.generation) {
        this.loading = false;
        this.timer = setTimeout((): void => { this.load(generation); }, 1000);
      }
    }
  }

  private updateResults(): void {
    const records = filterLogs(this.records, this.query);
    this.matchCount = records.length;
    this.source.update(records);
  }

  private async exportLogs(): Promise<void> {
    if (this.exporting) { return; }
    this.exporting = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) { throw new Error('无法打开文件保存窗口'); }
      if (await logService.exportLogs(context, filterLogs(this.records, this.query))) {
        feedbackService.success('日志已导出');
      }
    } catch (error) {
      feedbackService.error((error as Error).message || '导出失败，请重试');
    } finally { this.exporting = false; }
  }

  @Builder
  private actions() {
    HeaderIconButton({ icon: $r('app.media.action_export'), label: '导出当前搜索结果',
      available: this.matchCount > 0, busy: this.exporting, onActivate: (): void => { this.exportLogs(); } })
  }

  @Builder
  private logRow(record: LogRecord) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        Text(formatLogTime(record.time)).fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_secondary')).layoutWeight(1)
        Text(record.level.toUpperCase()).fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(record.level === LogLevel.ERROR ? $r('app.color.status_error') : $r('app.color.content_secondary'))
      }.width('100%')
      Text(record.message).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
        .fontColor($r('app.color.content_primary')).width('100%').wordBreak(WordBreak.BREAK_ALL)
        .copyOption(CopyOptions.LocalDevice)
    }.width('100%').padding(16).borderRadius(20).backgroundColor(this.theme.surface)
  }

  build() {
    Column() {
      SecondaryPageHeader({ title: '日志', contentPadding: this.contentPadding, onBack: this.onBack,
        actions: (): void => { this.actions(); } })
      Column({ space: 12 }) {
        TextInput({ placeholder: '搜索日志内容、等级或时间', text: this.query })
          .id('log-search').height(CONTROL_HEIGHT).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
          .placeholderFont({ size: themeFontSize(16, this.theme), family: this.theme.fontFamily })
          .fontColor($r('app.color.content_primary')).placeholderColor($r('app.color.content_secondary'))
          .backgroundColor(this.theme.surface).borderRadius(24).accessibilityText('搜索日志')
          .onChange((value: string): void => { this.query = value; this.updateResults(); })
        Text(this.loaded ? `${this.capture && this.level !== LogLevel.SILENT ? '捕获中' : '捕获已暂停'} · ` +
          `${LOG_LEVEL_LABELS[LOG_LEVELS.indexOf(this.level)]} · ${this.matchCount} / ${this.totalCount} 条` : '日志捕获与等级可在“常规”中设置')
          .fontSize(themeFontSize(13, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_secondary')).width('100%')
        Text('仅保留最近 500 条、64 KiB 正文，内核宿主退出后清空。导出当前搜索结果，内容可能包含域名和连接地址。')
          .fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_secondary')).width('100%')
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor($r('app.color.status_error')).width('100%')
          Button('重新读取').enabled(!this.loading).onClick((): void => { this.updateActivity(); })
        }
      }.padding({ left: this.contentPadding, right: this.contentPadding, bottom: 12 }).width('100%')
      Stack() {
        if (this.loading && !this.loaded) {
          LoadingProgress().width(40).height(40).color(this.theme.accent).accessibilityText('正在读取日志')
        } else if (this.matchCount === 0 && this.errorMessage.length === 0) {
          EmptyStateBackground({ icon: $r('app.media.nav_requests'),
            title: this.totalCount > 0 ? '没有匹配的日志' : '暂无日志',
            description: this.totalCount > 0 ? '尝试其他关键词。' :
              (this.capture && this.level !== LogLevel.SILENT ? '正在等待新的内核日志。' : '在设置 → 常规 → 日志中开启捕获，并选择非静默等级。') })
        }
        List({ space: 8 }) {
          LazyForEach(this.source, (record: LogRecord) => {
            ListItem() { this.logRow(record) }
          }, (record: LogRecord): string => `${record.id}:${record.time}`)
        }.width('100%').height('100%').contentEndOffset(32).scrollBar(BarState.Off)
      }.width('100%').layoutWeight(1).padding({ left: this.contentPadding, right: this.contentPadding })
    }.width('100%').height('100%').backgroundColor(this.theme.background)
      .onAreaChange((_old: Area, area: Area): void => {
        this.contentPadding = resolveResponsiveMetrics(resolveContentWidth(area.width)).pagePadding;
      })
  }
}
