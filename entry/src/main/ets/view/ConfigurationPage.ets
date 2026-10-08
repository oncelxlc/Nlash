import {
  DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES,
  MAX_PROFILE_UPDATE_INTERVAL_MINUTES,
  MIN_PROFILE_UPDATE_INTERVAL_MINUTES
} from '../constants/ProfileConstants';
import { formatProfileRelativeTime, getSubscriptionHost, profileUsageRatio } from '../utils/ProfileUtils';
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
  BUTTON_RADIUS, CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE
} from '../constants/UiConstants';

import { PageHeader } from '../components/PageHeader';
import { StatusBadge } from '../components/StatusBadge';
import { EmptyStateCard } from '../components/EmptyStateCard';

@Component
export struct ConfigurationPage {
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
  @State formError: string = '';
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribe: (() => void) | undefined = undefined;
  private editorBackUnsubscribe: (() => void) | undefined = undefined;

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
    if (id === this.activeProfileId || this.busyProfileId.length > 0) {
      return;
    }
    try {
      await profileStore.select(id);
      feedbackService.success('已切换活动配置');
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

  private requestCloseEditor(): void {
    if (!this.hasEditorChanges()) {
      this.closeEditorImmediately();
      return;
    }
    AlertDialog.show({
      title: '放弃修改',
      message: '当前修改尚未保存，确定关闭编辑器吗？',
      primaryButton: {
        value: '继续编辑',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '放弃修改',
        fontColor: $r('app.color.status_error'),
        action: (): void => {
          this.closeEditorImmediately();
        }
      }
    });
  }

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
    AlertDialog.show({
      title: '删除配置',
      message: `确定删除“${profile.name}”及其沙箱配置文件吗？`,
      primaryButton: {
        value: '取消',
        action: (): void => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.status_error'),
        action: (): void => {
          this.removeProfile(profile.id);
        }
      }
    });
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

  private formatBytes(value: number): string {
    if (value < 1024) {
      return `${value}B`;
    }
    const units: string[] = ['KB', 'MB', 'GB', 'TB'];
    let converted = value / 1024;
    let unitIndex = 0;
    while (converted >= 1024 && unitIndex < units.length - 1) {
      converted /= 1024;
      unitIndex += 1;
    }
    const digits = converted >= 10 ? 0 : 1;
    return `${converted.toFixed(digits)}${units[unitIndex]}`;
  }

  private usedBytes(profile: Profile): number {
    return Math.max(0, (profile.uploadBytes ?? 0) + (profile.downloadBytes ?? 0));
  }

  @Builder
  private headerActions() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.action_refresh')).width(20).height(20).fillColor($r('app.color.content_primary'))
      }
      .width(CONTROL_HEIGHT)
      .height(CONTROL_HEIGHT)
      .borderRadius(BUTTON_RADIUS)
      .backgroundColor($r('app.color.surface_muted'))
      .enabled(this.busyProfileId.length === 0 && this.hasSubscription())
      .accessibilityText('更新全部订阅')
      .onClick((): void => { this.updateAll(); })
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.action_add')).width(24).height(24).fillColor($r('app.color.accent_foreground'))
      }
      .width(CONTROL_HEIGHT)
      .height(CONTROL_HEIGHT)
      .borderRadius(BUTTON_RADIUS)
      .backgroundColor($r('app.color.action_primary'))
      .enabled(this.busyProfileId.length === 0)
      .accessibilityText('添加订阅或导入配置')
      .onClick((): void => { this.showAddOptions(); })
    }
  }

  @Builder
  private statusBanner() {
    if (this.busyProfileId.length > 0 && this.getStageLabel().length > 0) {
      Row({ space: 12 }) {
        LoadingProgress().width(20).height(20).color($r('app.color.nav_selected'))
        Text(this.getStageLabel()).fontSize(14).fontColor($r('app.color.nav_selected')).layoutWeight(1)
      }
      .width('100%')
      .padding(16)
      .borderRadius(BUTTON_RADIUS)
      .backgroundColor($r('app.color.nav_selected_background'))
    }
  }

  @Builder
  private profileCard(profile: Profile) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(profile.name)
          .fontSize(BODY_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
          .layoutWeight(1)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (profile.id === this.activeProfileId) {
          StatusBadge({ text: '当前使用', active: true })
        }
        Button({ type: ButtonType.Normal }) {
          Image($r('app.media.action_more'))
            .width(24).height(24).fillColor($r('app.color.content_secondary'))
        }
        .width(CONTROL_HEIGHT)
        .height(CONTROL_HEIGHT)
        .borderRadius(BUTTON_RADIUS)
        .backgroundColor(Color.Transparent)
        .enabled(this.busyProfileId.length === 0)
        .accessibilityText(`${profile.name} 的更多操作`)
        .bindMenu(this.profileActions(profile))
        .onTouch((event: TouchEvent): void => { event.stopPropagation(); })
      }
      .width('100%')
      if ((profile.totalBytes ?? 0) > 0 || (profile.expireAt ?? 0) > 0) {
        Row({ space: 8 }) {
          if ((profile.totalBytes ?? 0) > 0) {
            Text(`已用 ${this.formatBytes(this.usedBytes(profile))} / ${this.formatBytes(profile.totalBytes ?? 0)}`)
              .fontSize(CAPTION_FONT_SIZE)
              .fontColor($r('app.color.content_secondary'))
              .layoutWeight(1)
          } else {
            Blank()
          }
          if (profile.expireAt !== undefined && profile.expireAt > 0) {
            Text(`到期 ${new Date(profile.expireAt).toLocaleDateString()}`)
              .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
          }
        }
        .width('100%')
      }
      if ((profile.totalBytes ?? 0) > 0) {
        Progress({ value: profileUsageRatio(profile) * 100, total: 100, type: ProgressType.Linear })
          .width('100%')
          .color($r('app.color.nav_selected'))
          .backgroundColor($r('app.color.skeleton_background'))
      }
      Row({ space: 8 }) {
        Text(profile.type === ProfileType.LOCAL ? '本地 YAML' : getSubscriptionHost(profile.sourceUrl))
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(formatProfileRelativeTime(profile.lastUpdateAt))
          .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding({ left: 12, right: 8, top: 4, bottom: 8 })
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: 1, color: profile.id === this.activeProfileId ?
      $r('app.color.nav_selected') : $r('app.color.nav_divider') })
    .accessibilityText(`${profile.name}，${profile.id === this.activeProfileId ? '当前使用' : '点击设为活动配置'}`)
    .accessibilitySelected(profile.id === this.activeProfileId)
    .onClick((): void => { this.selectProfile(profile.id); })
  }

  @Builder
  private fieldLabel(label: string) {
    Text(label).fontSize(14).fontColor($r('app.color.content_secondary')).width('100%')
  }

  @Builder
  private editorFields() {
    Column({ space: 12 }) {
      this.fieldLabel('名称')
      TextInput({ placeholder: '配置名称', text: this.editName })
        .width('100%').height(CONTROL_HEIGHT)
        .fontColor($r('app.color.content_primary'))
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1, color: $r('app.color.control_border') })
        .borderRadius(BUTTON_RADIUS)
        .enabled(this.busyProfileId.length === 0)
        .accessibilityText('配置名称')
        .onChange((value: string): void => { this.editName = value; this.editorDirty = true; })
      if (this.editingProfile()?.type === ProfileType.SUBSCRIPTION) {
        this.fieldLabel('订阅 URL')
        TextInput({ placeholder: 'https://example.com/subscription', text: this.editUrl })
          .type(InputType.URL).width('100%').height(CONTROL_HEIGHT)
          .fontColor($r('app.color.content_primary'))
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 1, color: $r('app.color.control_border') })
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0)
          .accessibilityText('订阅 URL')
          .onChange((value: string): void => { this.editUrl = value; this.editorDirty = true; })
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('自动更新').fontSize(BODY_FONT_SIZE).fontColor($r('app.color.content_primary'))
            Text('启动、回到前台及到期后检查').fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
          }
          .layoutWeight(1).alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.editAutoUpdateEnabled })
            .selectedColor($r('app.color.nav_selected'))
            .enabled(this.busyProfileId.length === 0)
            .accessibilityText('自动更新订阅')
            .onChange((value: boolean): void => { this.editAutoUpdateEnabled = value; this.editorDirty = true; })
        }
        .width('100%').padding({ top: 12, bottom: 12 })
        this.fieldLabel(`更新间隔 · 分钟（${MIN_PROFILE_UPDATE_INTERVAL_MINUTES}–${MAX_PROFILE_UPDATE_INTERVAL_MINUTES}）`)
        TextInput({ placeholder: `${DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES}`, text: this.editIntervalMinutes })
          .type(InputType.Number).width('100%').height(CONTROL_HEIGHT)
          .fontColor($r('app.color.content_primary'))
          .backgroundColor($r('app.color.card_background'))
          .border({ width: 1, color: $r('app.color.control_border') })
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0)
          .accessibilityText('自动更新间隔，分钟')
          .onChange((value: string): void => { this.editIntervalMinutes = value; this.editorDirty = true; })
      } else {
        Text('本地 YAML 支持修改名称。').fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary')).width('100%')
      }
      this.statusBanner()
      if (this.formError.length > 0) {
        Text(this.formError).fontSize(14).fontColor($r('app.color.status_error')).width('100%')
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private editorContent() {
    Scroll() {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Button({ type: ButtonType.Normal }) {
            Image($r('app.media.action_back')).width(24).height(24).fillColor($r('app.color.content_primary'))
          }
          .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
          .backgroundColor($r('app.color.surface_muted'))
          .accessibilityText('返回配置列表')
          .onClick((): void => { this.requestCloseEditor(); })
          Text('编辑配置').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.content_primary'))
            .layoutWeight(1)
        }
        .width('100%')
        this.editorFields()
        Button(this.busyProfileId.length > 0 ? '保存中…' :
          (this.editingProfile()?.type === ProfileType.SUBSCRIPTION ? '保存并更新' : '保存名称'))
          .type(ButtonType.Normal).width('100%').height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
          .fontSize(BODY_FONT_SIZE).fontColor($r('app.color.accent_foreground')).backgroundColor($r('app.color.action_primary'))
          .enabled(this.busyProfileId.length === 0)
          .onClick((): void => { this.saveEditor(); })
      }
      .width('100%')
      .constraintSize({ maxWidth: 720, minHeight: '100%' })
      .alignItems(HorizontalAlign.Start)
      .padding({
        top: this.metrics.pagePadding, left: this.metrics.pagePadding, right: this.metrics.pagePadding,
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private mainContent() {
    Column({ space: this.metrics.sectionGap }) {
      PageHeader({
        title: $r('app.string.nav_configuration'), subtitle: `${this.profiles.length} 份配置 · 保存在本机`,
        actions: (): void => { this.headerActions(); }
      })
      this.statusBanner()
      if (this.profiles.length === 0) {
        EmptyStateCard({ title: '从一份配置开始', description: '点击右上角添加订阅或导入本地 YAML，校验通过后即可使用。' })
        Blank()
      } else {
        Text('长按拖动排序 · 更多操作可上移／下移')
          .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary')).width('100%')
        List({ space: this.metrics.cardGap }) {
          ForEach(this.profiles, (profile: Profile) => {
            ListItem() { this.profileCard(profile) }
          }, (profile: Profile): string => profile.id)
            .onMove(this.busyProfileId.length === 0 ? (from: number, to: number): void => {
              const profile = this.profiles[from];
              if (profile !== undefined) { this.moveProfile(profile.id, to); }
            } : undefined)
        }
        .lanes(this.metrics.profileColumns.split(' ').length, this.metrics.cardGap)
        .width('100%').layoutWeight(1)
        .contentEndOffset(this.metrics.pagePadding + FLOATING_NAVIGATION_INSET)
        .scrollBar(BarState.Auto)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%').height('100%')
    .padding({ top: this.metrics.pagePadding, left: this.metrics.pagePadding, right: this.metrics.pagePadding })
  }

  @Builder
  private addProfileSheet() {
    Column({ space: 12 }) {
      Text('添加订阅').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.content_primary')).width('100%')
      this.fieldLabel('名称 · 可选')
      TextInput({ placeholder: '配置名称', text: this.addName })
        .width('100%').height(CONTROL_HEIGHT)
        .fontColor($r('app.color.content_primary')).backgroundColor($r('app.color.surface_muted'))
        .border({ width: 1, color: $r('app.color.control_border') }).borderRadius(BUTTON_RADIUS)
        .enabled(!this.isAddingSubscription())
        .accessibilityText('订阅名称，可选')
        .onChange((value: string): void => { this.addName = value; })
      this.fieldLabel('订阅 URL')
      TextInput({ placeholder: 'https://example.com/subscription', text: this.addUrl })
        .width('100%').height(CONTROL_HEIGHT).type(InputType.URL)
        .fontColor($r('app.color.content_primary')).backgroundColor($r('app.color.surface_muted'))
        .border({ width: 1, color: $r('app.color.control_border') }).borderRadius(BUTTON_RADIUS)
        .enabled(!this.isAddingSubscription())
        .accessibilityText('订阅 URL')
        .onChange((value: string): void => { this.addUrl = value; })
      Text('名称留空时自动读取订阅标题。完整地址仅保存在应用沙箱，不显示在配置列表或写入日志。')
        .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary')).width('100%')
      if (this.formError.length > 0) {
        Text(this.formError).fontSize(14).fontColor($r('app.color.status_error')).width('100%')
      }
      Button(this.isAddingSubscription() ? this.getStageLabel() : '下载并校验')
        .type(ButtonType.Normal).width('100%').height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
        .fontSize(BODY_FONT_SIZE).fontColor($r('app.color.accent_foreground')).backgroundColor($r('app.color.action_primary'))
        .enabled(this.busyProfileId.length === 0 && this.addUrl.trim().length > 0)
        .onClick((): void => { this.addSubscription(); })
    }
    .alignItems(HorizontalAlign.Start).width('100%').padding(24)
  }

  @Builder
  private addSourceSheet() {
    Column({ space: 16 }) {
      Text('添加配置').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.content_primary')).width('100%')
      Text('选择配置来源').fontSize(BODY_FONT_SIZE).fontColor($r('app.color.content_secondary')).width('100%')
      Button('添加订阅')
        .type(ButtonType.Normal).width('100%').height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
        .fontSize(BODY_FONT_SIZE).fontColor($r('app.color.accent_foreground')).backgroundColor($r('app.color.action_primary'))
        .onClick((): void => { this.openAddSubscription(); })
      Button('导入本地 YAML')
        .type(ButtonType.Normal).width('100%').height(CONTROL_HEIGHT).borderRadius(BUTTON_RADIUS)
        .fontSize(BODY_FONT_SIZE).fontColor($r('app.color.nav_selected')).backgroundColor($r('app.color.nav_selected_background'))
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
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_old: Area, area: Area): void => { this.updateWidth(area.width); })
    .bindSheet(this.showProfileSheet, this.profileSheet(), {
      height: SheetSize.FIT_CONTENT,
      backgroundColor: $r('app.color.card_background'),
      onDisappear: (): void => {
        this.showProfileSheet = false;
        this.clearSheetInputs();
      }
    })
  }
}
