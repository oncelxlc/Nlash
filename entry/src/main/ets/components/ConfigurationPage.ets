import {
  DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES,
  formatProfileRelativeTime,
  getSubscriptionHost,
  MAX_PROFILE_UPDATE_INTERVAL_MINUTES,
  MIN_PROFILE_UPDATE_INTERVAL_MINUTES,
  Profile,
  ProfileEditDraft,
  profileUsageRatio,
  ProfileStoreSnapshot,
  ProfileType,
  ProfileUpdateStage
} from '../models/ProfileModels';
import { feedbackService } from '../services/FeedbackService';
import { configurationEditorService } from '../services/ConfigurationEditorService';
import { profileStore } from '../stores/ProfileStore';
import {
  ResponsiveMetrics,
  ResponsiveSizeClass,
  resolveResponsiveMetrics
} from '../ui/ResponsiveMetrics';
import { BUTTON_RADIUS } from '../ui/UiConstants';

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
    const numericWidth = typeof width === 'number' ? width :
      (typeof width === 'string' ? Number(width) : 0);
    this.metrics = resolveResponsiveMetrics(Number.isFinite(numericWidth) ? numericWidth : 0,
      this.forceExpanded);
  }

  private async addSubscription(): Promise<void> {
    const name = this.addName;
    const url = this.addUrl;
    try {
      await profileStore.addSubscription(name, url);
      this.showProfileSheet = false;
      feedbackService.success('配置已添加并通过校验');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
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

  private showAddOptions(): void {
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
      feedbackService.error(this.errorMessage(error));
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

  private profileSubline(profile: Profile): string {
    const updated = formatProfileRelativeTime(profile.lastUpdateAt);
    if (profile.type === ProfileType.LOCAL) {
      return `本地 YAML · ${updated}`;
    }
    return `${getSubscriptionHost(profile.sourceUrl)} · ${updated}`;
  }

  @Builder
  private pageHeader() {
    Row({ space: 12 }) {
      Text($r('app.string.nav_configuration'))
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.content_primary'))
        .layoutWeight(1)
      Button({ type: ButtonType.Normal }) {
        Image($r('app.media.action_refresh'))
          .width(22)
          .height(22)
          .fillColor($r('app.color.content_primary'))
      }
      .width(44)
      .height(44)
      .borderRadius(BUTTON_RADIUS)
      .backgroundColor($r('app.color.card_background'))
      .enabled(this.busyProfileId.length === 0 && this.hasSubscription())
      .accessibilityText('刷新全部订阅')
      .onClick((): void => {
        this.updateAll();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private statusBanner() {
    if (this.busyProfileId.length > 0 && this.getStageLabel().length > 0) {
      Row({ space: 10 }) {
        LoadingProgress()
          .width(18)
          .height(18)
        Text(this.getStageLabel())
          .fontSize(14)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding(12)
      .borderRadius(12)
      .backgroundColor($r('app.color.card_background'))
    }
  }

  @Builder
  private profileCard(profile: Profile) {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Text(profile.name)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text('⋮')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.content_secondary'))
          .width(40)
          .height(40)
          .textAlign(TextAlign.Center)
          .bindMenu(this.profileActions(profile))
          .onTouch((event: TouchEvent): void => {
            event.stopPropagation();
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if ((profile.totalBytes ?? 0) > 0) {
        Progress({ value: profileUsageRatio(profile) * 100, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(8)
          .color($r('app.color.nav_selected'))
          .backgroundColor($r('app.color.skeleton_background'))
        Row() {
          Text(`${this.formatBytes(this.usedBytes(profile))} / ${this.formatBytes(profile.totalBytes ?? 0)}`)
            .fontSize(14)
            .fontColor($r('app.color.content_secondary'))
            .layoutWeight(1)
          if (profile.expireAt !== undefined && profile.expireAt > 0) {
            Text(new Date(profile.expireAt).toLocaleDateString())
              .fontSize(14)
              .fontColor($r('app.color.content_secondary'))
          }
        }
        .width('100%')
      }

      Text(this.profileSubline(profile))
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.metrics.profileCardWidth)
    .padding(18)
    .margin({ bottom: this.metrics.cardGap })
    .borderRadius(18)
    .backgroundColor(profile.id === this.activeProfileId ?
      $r('app.color.nav_selected_background') : $r('app.color.card_background'))
    .border({
      width: profile.id === this.activeProfileId ? 2 : 1,
      color: profile.id === this.activeProfileId ?
        $r('app.color.nav_selected') : $r('app.color.skeleton_background')
    })
    .onClick((): void => {
      this.selectProfile(profile.id);
    })
  }

  @Builder
  private emptyState() {
    Column({ space: 12 }) {
      Text('还没有配置')
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
      Text('添加订阅后，Nlash 会先用 Mihomo Core 校验，再允许设为活动配置。')
        .fontSize(14)
        .fontColor($r('app.color.content_secondary'))
      Text('使用右下角的添加按钮选择订阅或本地 YAML。')
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(24)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private editorContent() {
    Column({ space: 20 }) {
      Row({ space: 12 }) {
        Button('‹')
          .type(ButtonType.Normal)
          .width(44)
          .height(44)
          .fontSize(28)
          .borderRadius(BUTTON_RADIUS)
          .backgroundColor(Color.Transparent)
          .fontColor($r('app.color.content_primary'))
          .onClick((): void => {
            this.requestCloseEditor();
          })
        Text('编辑配置')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.content_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text('名称')
        .fontSize(14)
        .fontColor($r('app.color.content_secondary'))
        .width('100%')
      TextInput({ placeholder: '配置名称', text: this.editName })
        .width('100%')
        .enabled(this.busyProfileId.length === 0)
        .onChange((value: string): void => {
          this.editName = value;
          this.editorDirty = true;
        })

      if (this.editingProfile()?.type === ProfileType.SUBSCRIPTION) {
        Text('订阅 URL')
          .fontSize(14)
          .fontColor($r('app.color.content_secondary'))
          .width('100%')
        TextInput({ placeholder: 'https://example.com/subscription', text: this.editUrl })
          .width('100%')
          .type(InputType.URL)
          .enabled(this.busyProfileId.length === 0)
          .onChange((value: string): void => {
            this.editUrl = value;
            this.editorDirty = true;
          })

        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('自动更新')
              .fontSize(16)
              .fontColor($r('app.color.content_primary'))
            Text('应用启动、回到前台及到期后检查')
              .fontSize(12)
              .fontColor($r('app.color.content_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.editAutoUpdateEnabled })
            .enabled(this.busyProfileId.length === 0)
            .onChange((value: boolean): void => {
              this.editAutoUpdateEnabled = value;
              this.editorDirty = true;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(`更新间隔（分钟，${MIN_PROFILE_UPDATE_INTERVAL_MINUTES}–${MAX_PROFILE_UPDATE_INTERVAL_MINUTES}）`)
          .fontSize(14)
          .fontColor($r('app.color.content_secondary'))
          .width('100%')
        TextInput({ placeholder: `${DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES}`, text: this.editIntervalMinutes })
          .width('100%')
          .type(InputType.Number)
          .enabled(this.busyProfileId.length === 0)
          .onChange((value: string): void => {
            this.editIntervalMinutes = value;
            this.editorDirty = true;
          })
      } else {
        Text('本地 YAML 只支持修改名称。')
          .fontSize(13)
          .fontColor($r('app.color.content_secondary'))
          .width('100%')
      }

      if (this.busyProfileId === this.editingProfileId && this.getStageLabel().length > 0) {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(18)
            .height(18)
          Text(this.getStageLabel())
            .fontSize(14)
            .fontColor($r('app.color.content_secondary'))
        }
        .width('100%')
      }

      Blank()
      Row({ space: 12 }) {
        Button('取消')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(48)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0)
          .onClick((): void => {
            this.requestCloseEditor();
          })
        Button(this.editingProfile()?.type === ProfileType.SUBSCRIPTION ? '保存并更新' : '保存')
          .type(ButtonType.Normal)
          .layoutWeight(1)
          .height(48)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0)
          .onClick((): void => {
            this.saveEditor();
          })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor($r('app.color.app_background'))
  }

  @Builder
  private mainContent() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll() {
        Column({ space: this.metrics.sectionGap }) {
          this.pageHeader()
          this.statusBanner()
          if (this.profiles.length === 0) {
            this.emptyState()
          } else {
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.profiles, (profile: Profile) => {
                this.profileCard(profile)
              }, (profile: Profile): string => profile.id)
            }
            .width('100%')
          }
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
        .constraintSize({ minHeight: '100%' })
        .padding({
          top: this.metrics.pagePadding,
          left: this.metrics.pagePadding,
          right: this.metrics.pagePadding,
          bottom: this.metrics.pagePadding + 80
        })
      }
      .width('100%')
      .height('100%')
      Button({ type: ButtonType.Normal }) {
        Text('+')
          .fontSize(30)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
      }
      .width(56)
      .height(56)
      .borderRadius(BUTTON_RADIUS)
      .backgroundColor($r('app.color.nav_selected'))
      .enabled(this.busyProfileId.length === 0)
      .accessibilityText('添加或导入配置')
      .margin({ right: this.metrics.pagePadding, bottom: this.metrics.pagePadding })
      .onClick((): void => {
        this.showAddOptions();
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private addProfileSheet() {
    Column({ space: 18 }) {
      Text('添加订阅')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.content_primary'))
        .width('100%')
      TextInput({ placeholder: '配置名称（可选）', text: this.addName })
        .width('100%')
        .onChange((value: string): void => {
          this.addName = value;
        })
      TextInput({ placeholder: 'https://example.com/subscription', text: this.addUrl })
        .width('100%')
        .type(InputType.URL)
        .onChange((value: string): void => {
          this.addUrl = value;
        })
      Text('名称留空时会优先读取订阅标题，再使用文件名或服务主机名。完整地址不会显示在卡片或写入日志。')
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
        .width('100%')
      Button() {
        Row({ space: 8 }) {
          if (this.isAddingSubscription()) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(Color.White)
          }
          Text(this.isAddingSubscription() ? this.getStageLabel() : '下载并校验')
            .fontColor(Color.White)
        }
      }
      .type(ButtonType.Normal)
      .borderRadius(BUTTON_RADIUS)
      .width('100%')
      .height(48)
      .enabled(this.busyProfileId.length === 0 && this.addUrl.trim().length > 0)
      .onClick((): void => {
        this.addSubscription();
      })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(24)
  }

  @Builder
  private addSourceSheet() {
    Column({ space: 14 }) {
      Text('添加配置')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.content_primary'))
        .width('100%')
      Text('请选择配置来源')
        .fontSize(14)
        .fontColor($r('app.color.content_secondary'))
        .width('100%')
      Button('添加订阅')
        .type(ButtonType.Normal)
        .borderRadius(BUTTON_RADIUS)
        .width('100%')
        .height(48)
        .onClick((): void => {
          this.openAddSubscription();
        })
      Button('导入本地 YAML')
        .type(ButtonType.Normal)
        .borderRadius(BUTTON_RADIUS)
        .width('100%')
        .height(48)
        .onClick((): void => {
          this.showProfileSheet = false;
          this.importLocal();
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(24)
  }

  @Builder
  private profileSheet() {
    if (this.sheetMode === 'SOURCE') {
      this.addSourceSheet()
    } else {
      this.addProfileSheet()
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (this.showEditor && this.metrics.sizeClass !== ResponsiveSizeClass.EXPANDED) {
        this.editorContent()
      } else {
        this.mainContent()
        if (this.showEditor) {
          Column() {
            this.editorContent()
          }
          .width(420)
          .height('100%')
          .shadow({ radius: 24, color: '#33000000', offsetX: -8, offsetY: 0 })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.updateWidth(newValue.width);
    })
    .bindSheet(this.showProfileSheet, this.profileSheet(), {
      height: SheetSize.FIT_CONTENT,
      onDisappear: (): void => {
        this.showProfileSheet = false;
        this.clearSheetInputs();
      }
    })
  }
}
