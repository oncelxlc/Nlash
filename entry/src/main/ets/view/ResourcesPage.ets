import { AppTheme } from '../model/ThemeModels';
import { themeMenu } from '../components/ThemeMenu';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { GeoResource, GeoResourceSnapshot, GeoSettingsPatch } from '../model/DiagnosticsModels';
import { RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { diagnosticsService } from '../services/DiagnosticsService';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { SecondaryPageHeader } from '../components/SecondaryPageHeader';
import { HeaderIconButton } from '../components/HeaderIconButton';
import { ResourceInputDialog } from '../components/ResourceInputDialog';
import { formatBytes } from '../utils/RuntimeUtils';
import { elapsedLabel } from '../utils/ActivityUtils';
import { revealTransition, selectionAnimation } from '../utils/AnimationUtils';
import { CONTROL_HEIGHT, DETAIL_CARD_RADIUS, CAPTION_FONT_SIZE } from '../constants/UiConstants';

interface ResourceRowData { resource: GeoResource; index: number; }

@Component
export struct ResourcesPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop @Watch('updateActivity') isActive: boolean = true;
  @Prop contentPadding: number = 16;
  onBack: () => void = (): void => {};
  @State snapshot: GeoResourceSnapshot = {
    resources: ['MMDB', 'ASN', 'GEOIP', 'GEOSITE'].map((kind: string): GeoResource =>
      ({ kind: kind, url: '', size: 0, updatedAt: 0 })),
    autoUpdate: false, intervalHours: 24, updating: false
  };
  @State available: boolean = false;
  @State updating: boolean = false;
  @State errorMessage: string = '';
  @State loadError: string = '';
  @State loaded: boolean = false;
  private active: boolean = false;
  private loading: boolean = false;
  private pendingSaves: number = 0;
  private saveQueue: Promise<void> = Promise.resolve();
  private lastRead: number = 0;
  private generation: number = 0;
  private unsubscribe: (() => void) | undefined;
  private dialog: CustomDialogController | undefined;

  aboutToAppear(): void { this.updateActivity(); }

  private updateActivity(): void {
    this.stopObserving();
    if (!this.isActive) { return; }
    this.active = true;
    this.lastRead = 0;
    this.unsubscribe = runtimeStore.subscribe((state: RuntimeStoreSnapshot): void => {
      if (this.available !== state.coreAvailable) { this.generation += 1; this.loaded = false; }
      this.available = state.coreAvailable;
      if (this.available && this.pendingSaves === 0 && Date.now() - this.lastRead >= 2000) { this.loadResources(); }
    });
  }

  aboutToDisappear(): void { this.stopObserving(); }

  private stopObserving(): void {
    this.active = false;
    this.generation += 1;
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.dialog?.close();
  }

  private async loadResources(): Promise<void> {
    if (this.loading) { return; }
    this.loading = true;
    this.lastRead = Date.now();
    const generation = this.generation;
    try {
      const snapshot = await diagnosticsService.resources();
      if (this.active && generation === this.generation && this.pendingSaves === 0) {
        this.snapshot = snapshot;
        this.loaded = true;
        this.loadError = '';
      }
    } catch (error) {
      if (this.active && generation === this.generation) { this.loadError = (error as Error).message; }
    } finally { this.loading = false; }
  }

  private async save(patch: GeoSettingsPatch): Promise<void> {
    this.pendingSaves += 1;
    this.generation += 1;
    const operation = this.saveQueue.then(async (): Promise<void> => {
      const snapshot = await diagnosticsService.saveResources(patch);
      if (this.active) { this.snapshot = snapshot; this.errorMessage = ''; }
    });
    this.saveQueue = operation.then((): void => {}, (): void => {});
    try { await operation; } finally { this.pendingSaves -= 1; }
  }

  private async toggleAutoUpdate(): Promise<void> {
    try { await this.save({ autoUpdate: !this.snapshot.autoUpdate }); }
    catch (error) { feedbackService.error((error as Error).message || '保存失败，请重试'); }
  }

  private openEditor(title: string, value: string, interval: boolean): void {
    this.dialog = new CustomDialogController({
      builder: ResourceInputDialog({ title: title, initialInput: value, interval: interval,
        onSubmit: async (input: string): Promise<void> => {
          if (interval) { await this.save({ intervalHours: Number(input) }); }
          else {
            const urls: Record<string, string> = {};
            urls[title] = input;
            await this.save({ urls: urls });
          }
        } }),
      customStyle: true, autoCancel: false, alignment: DialogAlignment.Center,
      openAnimation: selectionAnimation(220), closeAnimation: selectionAnimation(140)
    });
    this.dialog.open();
  }

  private async updateResources(): Promise<void> {
    if (this.updating || this.snapshot.updating) { return; }
    this.updating = true;
    this.errorMessage = '';
    try {
      await diagnosticsService.updateResources();
      feedbackService.success('资源已更新，下次启动 Core 时使用');
    } catch (error) {
      if (this.active) { this.errorMessage = (error as Error).message || '更新失败，请重试'; }
      feedbackService.error((error as Error).message || '更新失败，请重试');
    } finally {
      this.updating = false;
      if (this.active && this.available) { this.loadResources(); }
    }
  }

  @Builder
  private updateMenu() {
    themeMenu([
      { value: `自动更新：${this.snapshot.autoUpdate ? '开启' : '关闭'}`, icon: $r('app.media.action_switch'),
        action: (): void => { this.toggleAutoUpdate(); } },
      { value: `自动更新间隔 · ${this.snapshot.intervalHours} 小时`, icon: $r('app.media.nav_requests'),
        action: (): void => { this.openEditor('自动更新间隔', this.snapshot.intervalHours.toString(), true); } }
    ], this.theme)
  }

  @Builder
  private actions() {
    Row({ space: 8 }) {
      HeaderIconButton({ icon: $r('app.media.action_refresh'), label: '更新 Geo 资源',
        available: this.available && this.loaded, busy: this.updating || this.snapshot.updating,
        onActivate: (): void => { this.updateResources(); } })
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.action_more')).width(24).height(24)
          .fillColor($r('app.color.content_primary')).accessibilityLevel('no')
      }
      .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).padding(0).backgroundColor(this.theme.surface)
      .accessibilityText('资源更新设置')
      .enabled(this.available && this.loaded && !this.updating && !this.snapshot.updating)
      .bindMenu(this.updateMenu(), { backgroundColor: this.theme.surface })
    }
  }

  @Builder
  private resourceRow(data: ResourceRowData) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        Column({ space: 4 }) {
          Text(data.resource.kind).fontSize(themeFontSize(20, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_primary')).width('100%')
          Text(this.available ? (this.loaded ? elapsedLabel(data.resource.updatedAt) : '正在读取…') : 'Core 就绪后读取')
            .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).width('100%')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text(data.resource.updatedAt > 0 ? formatBytes(data.resource.size) : '--').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_secondary'))
      }.width('100%')
    }
    .width('100%').constraintSize({ minHeight: 80 }).padding(20).borderRadius(0).backgroundColor(Color.Transparent)
    .enabled(this.available && this.loaded && !this.updating && !this.snapshot.updating)
    .accessibilityText(`${data.resource.kind}，${elapsedLabel(data.resource.updatedAt)}，编辑下载地址`)
    .onClick((): void => { this.openEditor(data.resource.kind, data.resource.url, false); })
    if (data.index < this.snapshot.resources.length - 1) {
      Divider().color(this.theme.divider).padding({ left: 20, right: 20 })
    }
  }

  build() {
    Column() {
      SecondaryPageHeader({ title: '资源', contentPadding: this.contentPadding,
        onBack: this.onBack, actions: (): void => { this.actions(); } })
      Scroll() {
        Column({ space: 20 }) {
          Text('Geo').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).width('100%').padding({ left: 16 })
          Column() {
            ForEach(this.snapshot.resources, (resource: GeoResource, index: number) => {
              this.resourceRow({ resource: this.snapshot.resources[index], index: index })
            }, (resource: GeoResource): string => resource.kind)
          }.width('100%').borderRadius(DETAIL_CARD_RADIUS).clip(true).backgroundColor(this.theme.surface)
          if (this.updating || this.snapshot.updating) {
            Row({ space: 12 }) {
              LoadingProgress().width(20).height(20).color($r('app.color.content_primary'))
              Text('正在下载并校验资源…').fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
            }.width('100%').transition(revealTransition())
          }
          if (this.errorMessage.length > 0 || this.loadError.length > 0) {
            Text(this.errorMessage || this.loadError).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.status_error')).width('100%')
              .transition(revealTransition())
          }
          Text(this.available ?
            `点按资源可编辑下载源。${this.snapshot.autoUpdate ? `Core 运行时每 ${this.snapshot.intervalHours} 小时自动更新。` : '自动更新已关闭。'}更新的文件将在下次启动 Core 时使用。` :
            '请先启动 Core，再读取或更新 Geo 资源。')
            .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).width('100%')
        }.width('100%').padding({ top: 24, bottom: 32, left: this.contentPadding, right: this.contentPadding })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).align(Alignment.Top)
    }.width('100%').height('100%').backgroundColor(this.theme.background)
  }
}
