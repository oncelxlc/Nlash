import { AppTheme } from '../model/ThemeModels';
import { ThemeAlertDialog } from '../components/ThemeAlertDialog';
import { themeMenu } from '../components/ThemeMenu';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import {
  DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES,
  MAX_PROFILE_UPDATE_INTERVAL_MINUTES,
  MIN_PROFILE_UPDATE_INTERVAL_MINUTES
} from '../constants/ProfileConstants';
import {
  formatProfileBytes, formatProfileExpiry, formatProfileRelativeTime, getSubscriptionHost
} from '../utils/ProfileUtils';
import {
  Profile,
  ProfileEditDraft,
  ProfileStoreSnapshot,
  ProfileType,
  ProfileUpdateStage
} from '../model/ProfileModels';
import { feedbackService } from '../services/FeedbackService';
import { configurationEditorService } from '../services/ConfigurationEditorService';
import { profileStore } from '../stores/ProfileStore';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveResponsiveMetrics, resolveContentWidth } from '../utils/ResponsiveUtils';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, BODY_FONT_SIZE, CAPTION_FONT_SIZE,
  HEADER_ACTION_SIZE, HEADER_ACTION_ICON_SIZE, HEADER_CONTENT_HEIGHT, PAGE_TITLE_SIZE
} from '../constants/UiConstants';

import { PageHeader } from '../components/PageHeader';
import { FadingScrollLayout } from '../components/FadingScrollLayout';
import { EmptyStateBackground } from '../components/EmptyStateBackground';

/** 配置管理页面，编辑草稿独立于 Store，下载、保存与活动配置切换统一交给 ProfileStore。 */
@Component
export struct ConfigurationPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @State headerInset: number = 0;
  @Prop forceExpanded: boolean = false;
  @State profiles: Profile[] = [];
  @State activeProfileId: string = '';
  @State stage: ProfileUpdateStage = ProfileUpdateStage.IDLE;
  @State busyProfileId: string = '';
  @State showProfileSheet: boolean = false;
  @State sheetMode: string = 'SOURCE';
  @State addName: string = '';
  @State addUrl: string = '';
  @State showEditor: boolean = false;
  @State editingProfileId: string = '';
  @State editName: string = '';
  @State editUrl: string = '';
  @State editAutoUpdateEnabled: boolean = false;
  @State editIntervalMinutes: string = `${DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES}`;
  @State editorDirty: boolean = false;
  @State managingProfiles: boolean = false;
  @State formError: string = '';
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribe: (() => void) | undefined = undefined;
  private editorBackUnsubscribe: (() => void) | undefined = undefined;
  private alertDialog: CustomDialogController | undefined;

  aboutToAppear(): void {
    this.editorBackUnsubscribe = configurationEditorService.bind((): void => {
      this.requestCloseEditor();
    });
    this.unsubscribe = profileStore.subscribe((snapshot: ProfileStoreSnapshot): void => {
      this.profiles = snapshot.profiles;
      this.activeProfileId = snapshot.activeProfileId;
      this.stage = snapshot.stage;
      this.busyProfileId = snapshot.busyProfileId;
      if (this.showEditor && this.editingProfile() === undefined) {
        this.closeEditorImmediately();
      }
    });
  }

  aboutToDisappear(): void {
    this.alertDialog?.close();
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.editorBackUnsubscribe?.();
    this.editorBackUnsubscribe = undefined;
  }

  onBackPress(): boolean {
    if (!this.showEditor) {
      return false;
    }
    this.requestCloseEditor();
    return true;
  }

  private updateWidth(width: Length): void {
    this.metrics = resolveResponsiveMetrics(resolveContentWidth(width), this.forceExpanded);
  }

  private async addSubscription(): Promise<void> {
    this.formError = '';
    const name = this.addName;
    const url = this.addUrl;
    try {
      await profileStore.addSubscription(name, url);
      this.showProfileSheet = false;
      feedbackService.success('配置已添加并通过校验');
    } catch (error) {
      this.formError = this.errorMessage(error);
      feedbackService.error(this.formError);
    }
  }

  private async importLocal(): Promise<void> {
    try {
      await profileStore.importLocal();
      feedbackService.success('本地配置已导入并通过校验');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async updateProfile(id: string): Promise<void> {
    try {
      await profileStore.update(id);
      feedbackService.success('订阅已更新并通过校验');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async updateAll(): Promise<void> {
    try {
      await profileStore.updateAll();
      feedbackService.success('全部订阅已更新并通过校验');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async selectProfile(id: string): Promise<void> {
    if (this.busyProfileId.length > 0) {
      return;
    }
    try {
      await profileStore.select(id);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async moveProfile(id: string, to: number): Promise<void> {
    try {
      await profileStore.move(id, to);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private showAddOptions(): void {
    this.formError = '';
    this.sheetMode = 'SOURCE';
    this.showProfileSheet = true;
  }

  private openAddSubscription(): void {
    this.sheetMode = 'ADD';
    this.showProfileSheet = true;
  }

  private hasSubscription(): boolean {
    return this.profiles.some((profile: Profile): boolean => profile.type === ProfileType.SUBSCRIPTION);
  }

  private editingProfile(): Profile | undefined {
    return this.profiles.find((profile: Profile): boolean => profile.id === this.editingProfileId);
  }

  // 复制到表单字段，取消编辑不会修改已保存的配置元数据。
  private openEditor(profile: Profile): void {
    this.formError = '';
    this.editingProfileId = profile.id;
    this.editName = profile.name;
    this.editUrl = profile.sourceUrl;
    this.editAutoUpdateEnabled = profile.autoUpdateEnabled;
    this.editIntervalMinutes = `${profile.updateIntervalMinutes}`;
    this.editorDirty = false;
    this.showEditor = true;
    configurationEditorService.setOpen(true);
  }

  private closeEditorImmediately(): void {
    this.showEditor = false;
    this.editingProfileId = '';
    this.editorDirty = false;
    configurationEditorService.setOpen(false);
  }

  /** 系统返回与页面关闭共用未保存检查，确认放弃后才清空编辑上下文。 */
  private requestCloseEditor(): void {
    if (!this.hasEditorChanges()) {
      this.closeEditorImmediately();
      return;
    }
    this.alertDialog = new CustomDialogController({
      builder: ThemeAlertDialog({ title: '放弃修改', message: '当前修改尚未保存，确定关闭编辑器吗？',
        cancelLabel: '继续编辑', confirmLabel: '放弃修改', destructive: true,
        onConfirm: (): void => { this.closeEditorImmediately(); } }),
      customStyle: true, alignment: DialogAlignment.Center
    });
    this.alertDialog.open();
  }

  // 本地配置仅支持重命名，不把订阅专用字段计入未保存变化。
  private hasEditorChanges(): boolean {
    const profile = this.editingProfile();
    if (profile === undefined) {
      return false;
    }
    if (this.editName !== profile.name) {
      return true;
    }
    if (profile.type === ProfileType.LOCAL) {
      return false;
    }
    return this.editUrl !== profile.sourceUrl ||
      this.editAutoUpdateEnabled !== profile.autoUpdateEnabled ||
      Number(this.editIntervalMinutes) !== profile.updateIntervalMinutes;
  }

  private async saveEditor(): Promise<void> {
    this.formError = '';
    const profile = this.editingProfile();
    if (profile === undefined) {
      return;
    }
    const interval = Number(this.editIntervalMinutes);
    const draft: ProfileEditDraft = {
      name: this.editName,
      sourceUrl: profile.type === ProfileType.SUBSCRIPTION ? this.editUrl : profile.sourceUrl,
      autoUpdateEnabled: profile.type === ProfileType.SUBSCRIPTION ? this.editAutoUpdateEnabled : false,
      updateIntervalMinutes: profile.type === ProfileType.SUBSCRIPTION ? interval : profile.updateIntervalMinutes
    };
    try {
      await profileStore.saveAndUpdate(profile.id, draft);
      this.editorDirty = false;
      this.closeEditorImmediately();
      feedbackService.success(profile.type === ProfileType.SUBSCRIPTION ? '配置已保存并更新' : '配置已重命名');
    } catch (error) {
      this.formError = this.errorMessage(error);
      feedbackService.error(this.formError);
    }
  }

  private confirmRemove(profile: Profile): void {
    this.alertDialog = new CustomDialogController({
      builder: ThemeAlertDialog({ title: '删除配置', message: `确定删除“${profile.name}”及其沙箱配置文件吗？`,
        confirmLabel: '删除', destructive: true, onConfirm: (): void => { this.removeProfile(profile.id); } }),
      customStyle: true, alignment: DialogAlignment.Center
    });
    this.alertDialog.open();
  }

  private async removeProfile(id: string): Promise<void> {
    try {
      await profileStore.remove(id);
      feedbackService.success('配置已删除');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private profileActions(profile: Profile): MenuElement[] {
    const index = this.profiles.findIndex((item: Profile): boolean => item.id === profile.id);
    return [
      {
        value: '编辑',
        enabled: this.busyProfileId.length === 0,
        action: (): void => {
          this.openEditor(profile);
        }
      },
      {
        value: '更新',
        enabled: this.busyProfileId.length === 0 && profile.type === ProfileType.SUBSCRIPTION,
        action: (): void => {
          this.updateProfile(profile.id);
        }
      },
      {
        value: '上移',
        enabled: this.busyProfileId.length === 0 && index > 0,
        action: (): void => { this.moveProfile(profile.id, index - 1); }
      },
      {
        value: '下移',
        enabled: this.busyProfileId.length === 0 && index < this.profiles.length - 1,
        action: (): void => { this.moveProfile(profile.id, index + 1); }
      },
      {
        value: '删除',
        enabled: this.busyProfileId.length === 0,
        action: (): void => {
          this.confirmRemove(profile);
        }
      }
    ];
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : '配置操作失败';
  }

  private clearSheetInputs(): void {
    this.addName = '';
    this.addUrl = '';
    this.sheetMode = 'SOURCE';
  }

  private isAddingSubscription(): boolean {
    return this.busyProfileId === 'new';
  }

  private getStageLabel(): string {
    switch (this.stage) {
      case ProfileUpdateStage.DOWNLOADING:
        return '正在下载订阅';
      case ProfileUpdateStage.DOWNLOADED:
        return '下载完成';
      case ProfileUpdateStage.VALIDATING:
        return '正在校验配置';
      case ProfileUpdateStage.APPLYING:
        return '正在应用配置';
      case ProfileUpdateStage.APPLIED:
        return '配置已应用';
      case ProfileUpdateStage.PERSISTING:
        return '正在保存设置';
      default:
        return '';
    }
  }

  private usedBytes(profile: Profile): number {
    return Math.max(0, (profile.uploadBytes ?? 0) + (profile.downloadBytes ?? 0));
  }

  @Builder
  private headerActions() {
    Row({ space: 8 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.action_add_circle')).width(24).height(24)
            .fillColor($r('app.color.content_primary'))
            .accessibilityLevel('no')
        }
        .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).padding(0)
        .backgroundColor(Color.Transparent)
        .enabled(this.busyProfileId.length === 0)
        .accessibilityText('添加订阅或导入配置')
        .onClick((): void => { this.showAddOptions(); })
        Button({ type: ButtonType.Circle }) {
          if (this.busyProfileId.length > 0 && this.hasSubscription()) {
            LoadingProgress().width(24).height(24).color($r('app.color.content_primary'))
          } else {
            Image($r('app.media.action_refresh')).width(24).height(24)
              .fillColor($r('app.color.content_primary'))
              .accessibilityLevel('no')
          }
        }
        .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).padding(0)
        .backgroundColor(Color.Transparent)
        .enabled(this.busyProfileId.length === 0 && this.hasSubscription())
        .accessibilityText('更新全部订阅')
        .onClick((): void => { this.updateAll(); })
      }
      .borderRadius(CONTROL_HEIGHT / 2)
      .backgroundColor(this.theme.surface)
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.action_sort')).width(24).height(24)
          .fillColor(this.managingProfiles ? this.theme.accent : $r('app.color.content_primary'))
          .accessibilityLevel('no')
      }
      .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).padding(0)
      .backgroundColor(this.managingProfiles ? this.theme.accentSurface : this.theme.surface)
      .enabled(this.busyProfileId.length === 0 && this.profiles.length > 0)
      .accessibilityText(this.managingProfiles ? '完成配置管理与排序' : '管理配置与排序')
      .accessibilitySelected(this.managingProfiles)
      .onClick((): void => { this.managingProfiles = !this.managingProfiles; })
    }
  }

  @Builder
  private statusBanner(contentPadding: number = 0) {
    if (this.busyProfileId.length > 0 && this.getStageLabel().length > 0) {
      Column() {
        Row({ space: 12 }) {
          LoadingProgress().width(20).height(20).color(this.theme.accent)
          Text(this.getStageLabel()).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor(this.theme.accent).layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .borderRadius(BUTTON_RADIUS)
        .backgroundColor(this.theme.muted)
      }
      .width('100%')
      .padding({ left: contentPadding, right: contentPadding })
    }
  }

  @Builder
  private profileCard(profile: Profile) {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              Text(profile.name)
                .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.content_primary'))
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ right: 8 })
              if (formatProfileExpiry(profile.expireAt ?? 0).length > 0) {
                Text(formatProfileExpiry(profile.expireAt ?? 0))
                  .fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
                  .fontColor(this.theme.accent)
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(16)
                  .backgroundColor(this.theme.accentSurface)
                  .maxLines(1)
              }
            }
            .width('100%')
            Text((profile.totalBytes ?? 0) > 0 ?
              `${formatProfileBytes(this.usedBytes(profile))} / ${formatProfileBytes(profile.totalBytes ?? 0)}` :
              (profile.type === ProfileType.LOCAL ? '本地 YAML' : getSubscriptionHost(profile.sourceUrl)))
              .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
              .fontColor($r('app.color.content_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          if (profile.type === ProfileType.SUBSCRIPTION || profile.id === this.busyProfileId) {
            Text(profile.id === this.busyProfileId ? (this.getStageLabel() || '处理中…') :
              formatProfileRelativeTime(profile.lastUpdateAt))
              .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
              .fontColor($r('app.color.content_secondary'))
              .constraintSize({ maxWidth: 88 })
              .textAlign(TextAlign.End)
          }
          if (profile.id === this.busyProfileId) {
            LoadingProgress().width(28).height(28).color(this.theme.accent)
          } else if (profile.id === this.activeProfileId) {
            Image($r('app.media.action_check'))
              .width(28).height(28).padding(5)
              .fillColor(this.theme.onAccent)
              .borderRadius(14)
              .backgroundColor(this.theme.accent)
              .accessibilityLevel('no')
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .constraintSize({ minHeight: 76 })
      }
      .layoutWeight(1).padding(0).borderRadius(32)
      .backgroundColor(this.theme.surface)
      .enabled(this.busyProfileId.length === 0)
      .accessibilityText(`${profile.name}，${profile.id === this.activeProfileId ? '当前使用' : '点击设为活动配置'}` +
        (profile.id === this.busyProfileId ? `，${this.getStageLabel() || '正在处理配置'}` : ''))
      .accessibilitySelected(profile.id === this.activeProfileId)
      .onClick((): void => { this.selectProfile(profile.id); })
      if (this.managingProfiles) {
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.action_more'))
            .width(24).height(24).fillColor($r('app.color.content_secondary'))
            .accessibilityLevel('no')
        }
        .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT)
        .backgroundColor(Color.Transparent)
        .margin({ right: 8 })
        .enabled(this.busyProfileId.length === 0)
        .accessibilityText(`${profile.name} 的更多操作`)
        .bindMenu(this.profileMenu(profile), { backgroundColor: this.theme.surface })
      }
    }
    .width('100%')
    .borderRadius(32)
    .backgroundColor(this.theme.surface)
  }

  @Builder
  private profileMenu(profile: Profile) {
    themeMenu(this.profileActions(profile), this.theme)
  }

  @Builder
  private fieldLabel(label: string) {
    Text(label).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).width('100%')
  }

  @Builder
  private editorFields() {
    Column({ space: 12 }) {
      this.fieldLabel('名称')
      TextInput({ placeholder: '配置名称', text: this.editName })
        .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
        .placeholderFont({ size: themeFontSize(BODY_FONT_SIZE, this.theme), family: this.theme.fontFamily })
        .width('100%').height(CONTROL_HEIGHT)
        .fontColor($r('app.color.content_primary'))
        .backgroundColor(this.theme.surface)
        .borderRadius(BUTTON_RADIUS)
        .enabled(this.busyProfileId.length === 0)
        .accessibilityText('配置名称')
        .onChange((value: string): void => { this.editName = value; this.editorDirty = true; })
      if (this.editingProfile()?.type === ProfileType.SUBSCRIPTION) {
        this.fieldLabel('订阅 URL')
        TextInput({ placeholder: 'https://example.com/subscription', text: this.editUrl })
          .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
          .placeholderFont({ size: themeFontSize(BODY_FONT_SIZE, this.theme), family: this.theme.fontFamily })
          .type(InputType.URL).width('100%').height(CONTROL_HEIGHT)
          .fontColor($r('app.color.content_primary'))
          .backgroundColor(this.theme.surface)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0)
          .accessibilityText('订阅 URL')
          .onChange((value: string): void => { this.editUrl = value; this.editorDirty = true; })
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('自动更新').fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_primary'))
            Text('启动、回到前台及到期后检查').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.editAutoUpdateEnabled })
            .selectedColor(this.theme.accent)
            .enabled(this.busyProfileId.length === 0)
            .accessibilityText('自动更新订阅')
            .onChange((value: boolean): void => { this.editAutoUpdateEnabled = value; this.editorDirty = true; })
        }
        .width('100%').padding({ top: 12, bottom: 12 })
        this.fieldLabel(`更新间隔 · 分钟（${MIN_PROFILE_UPDATE_INTERVAL_MINUTES}–${MAX_PROFILE_UPDATE_INTERVAL_MINUTES}）`)
        TextInput({ placeholder: `${DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES}`, text: this.editIntervalMinutes })
          .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
          .placeholderFont({ size: themeFontSize(BODY_FONT_SIZE, this.theme), family: this.theme.fontFamily })
          .type(InputType.Number).width('100%').height(CONTROL_HEIGHT)
          .fontColor($r('app.color.content_primary'))
          .backgroundColor(this.theme.surface)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0)
          .accessibilityText('自动更新间隔，分钟')
          .onChange((value: string): void => { this.editIntervalMinutes = value; this.editorDirty = true; })
      }
      this.statusBanner()
      if (this.formError.length > 0) {
        Text(this.formError).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.status_error')).width('100%')
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private editorHeader() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.action_back')).width(HEADER_ACTION_ICON_SIZE).height(HEADER_ACTION_ICON_SIZE)
          .fillColor($r('app.color.content_primary'))
      }
      .width(HEADER_ACTION_SIZE).height(HEADER_ACTION_SIZE).padding(0).borderRadius(8)
      .responseRegion({ x: -8, y: -8, width: CONTROL_HEIGHT, height: CONTROL_HEIGHT })
      .backgroundColor(this.theme.muted)
      .accessibilityText('返回配置列表')
      .onClick((): void => { this.requestCloseEditor(); })
      Text('编辑配置').fontSize(themeFontSize(PAGE_TITLE_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold).fontColor($r('app.color.content_primary'))
        .constraintSize({ minHeight: HEADER_CONTENT_HEIGHT })
        .layoutWeight(1)
    }
    .width('100%')
    .constraintSize({ maxWidth: 720 })
    .padding({
      top: this.metrics.pagePadding, left: this.metrics.pagePadding, right: this.metrics.pagePadding
    })
  }

  @Builder
  private editorScrollContent() {
    Scroll() {
      Column({ space: 16 }) {
        this.editorFields()
        Button(this.busyProfileId.length > 0 ? '保存中…' :
          (this.editingProfile()?.type === ProfileType.SUBSCRIPTION ? '保存并更新' : '保存名称'))
          .type(ButtonType.Normal).width('100%').height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
          .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor(this.theme.onAccent).backgroundColor(this.theme.accent)
          .enabled(this.busyProfileId.length === 0)
          .onClick((): void => { this.saveEditor(); })
      }
      .width('100%')
      .constraintSize({ maxWidth: 720, minHeight: '100%' })
      .alignItems(HorizontalAlign.Start)
      .padding({
        top: this.headerInset, left: this.metrics.pagePadding, right: this.metrics.pagePadding,
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET
      })
    }
    .width('100%').height('100%')
    .scrollBar(BarState.Off)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private editorContent() {
    FadingScrollLayout({
      topInset: $headerInset,
      header: (): void => { this.editorHeader(); },
      content: (): void => { this.editorScrollContent(); }
    })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private mainHeader() {
    Column({ space: this.metrics.sectionGap }) {
      PageHeader({
        title: $r('app.string.nav_configuration'), contentPadding: this.metrics.pagePadding,
        actions: (): void => { this.headerActions(); }
      })
      if (this.busyProfileId === 'import') {
        this.statusBanner(this.metrics.pagePadding)
      }
    }
    .width('100%')
  }

  @Builder
  private profileList() {
    if (this.profiles.length === 0) {
      Stack() {
        EmptyStateBackground({
          icon: $r('app.media.nav_configuration'), title: '暂无配置'
        })
      }
      .width('100%').height('100%')
      .padding({ top: this.headerInset, left: this.metrics.pagePadding, right: this.metrics.pagePadding })
    } else {
      List({ space: this.metrics.cardGap }) {
        ForEach(this.profiles, (profile: Profile) => {
          ListItem() { this.profileCard(profile) }
        }, (profile: Profile): string => `${profile.id}:${profile.updatedAt}`)
          .onMove(this.busyProfileId.length === 0 ? (from: number, to: number): void => {
            const profile = this.profiles[from];
            if (profile !== undefined) { this.moveProfile(profile.id, to); }
          } : undefined)
      }
      .lanes(this.metrics.profileColumns.split(' ').length, this.metrics.cardGap)
      .width('100%').height('100%')
      .padding({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
      .contentStartOffset(this.headerInset)
      .contentEndOffset(this.metrics.pagePadding + FLOATING_NAVIGATION_INSET)
      .scrollBar(BarState.Off)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  private mainContent() {
    FadingScrollLayout({
      topInset: $headerInset,
      gap: this.metrics.sectionGap,
      header: (): void => { this.mainHeader(); },
      content: (): void => { this.profileList(); }
    })
  }

  @Builder
  private addProfileSheet() {
    Column({ space: 12 }) {
      Text('添加订阅').fontSize(themeFontSize(24, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold).fontColor($r('app.color.content_primary')).width('100%')
      this.fieldLabel('名称 · 可选')
      TextInput({ placeholder: '配置名称', text: this.addName })
        .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
        .placeholderFont({ size: themeFontSize(BODY_FONT_SIZE, this.theme), family: this.theme.fontFamily })
        .width('100%').height(CONTROL_HEIGHT)
        .fontColor($r('app.color.content_primary')).backgroundColor(this.theme.muted)
        .borderRadius(BUTTON_RADIUS)
        .enabled(!this.isAddingSubscription())
        .accessibilityText('订阅名称，可选')
        .onChange((value: string): void => { this.addName = value; })
      this.fieldLabel('订阅 URL')
      TextInput({ placeholder: 'https://example.com/subscription', text: this.addUrl })
        .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
        .placeholderFont({ size: themeFontSize(BODY_FONT_SIZE, this.theme), family: this.theme.fontFamily })
        .width('100%').height(CONTROL_HEIGHT).type(InputType.URL)
        .fontColor($r('app.color.content_primary')).backgroundColor(this.theme.muted)
        .borderRadius(BUTTON_RADIUS)
        .enabled(!this.isAddingSubscription())
        .accessibilityText('订阅 URL')
        .onChange((value: string): void => { this.addUrl = value; })
      if (this.formError.length > 0) {
        Text(this.formError).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.status_error')).width('100%')
      }
      Button(this.isAddingSubscription() ? this.getStageLabel() : '下载并校验')
        .type(ButtonType.Normal).width('100%').height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
        .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor(this.theme.onAccent).backgroundColor(this.theme.accent)
        .enabled(this.busyProfileId.length === 0 && this.addUrl.trim().length > 0)
        .onClick((): void => { this.addSubscription(); })
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(24)
  }

  @Builder
  private addSourceSheet() {
    Column({ space: 16 }) {
      Text('添加配置').fontSize(themeFontSize(24, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold).fontColor($r('app.color.content_primary')).width('100%')
      Button('添加订阅')
        .type(ButtonType.Normal).width('100%').height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
        .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor(this.theme.onAccent).backgroundColor(this.theme.accent)
        .onClick((): void => { this.openAddSubscription(); })
      Button('导入本地 YAML')
        .type(ButtonType.Normal).width('100%').height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
        .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor(this.theme.accent).backgroundColor(this.theme.muted)
        .onClick((): void => { this.showProfileSheet = false; this.importLocal(); })
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(24)
  }

  @Builder
  private profileSheet() {
    if (this.sheetMode === 'SOURCE') { this.addSourceSheet() } else { this.addProfileSheet() }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      if (this.showEditor) { this.editorContent() } else { this.mainContent() }
    }
    .width('100%').height('100%')
    .backgroundColor(this.theme.background)
    .onAreaChange((_old: Area, area: Area): void => { this.updateWidth(area.width); })
    .bindSheet(this.showProfileSheet, this.profileSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: this.theme.surface,
      onDisappear: (): void => {
        this.showProfileSheet = false;
        this.clearSheetInputs();
      }
    })
  }
}
