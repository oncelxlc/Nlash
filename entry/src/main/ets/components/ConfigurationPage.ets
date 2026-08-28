import {
  getSubscriptionHost,
  Profile,
  ProfileStoreSnapshot,
  ProfileType,
  ProfileUpdateStage
} from '../models/ProfileModels';
import { feedbackService } from '../services/FeedbackService';
import { profileStore } from '../stores/ProfileStore';
import { ResponsiveMetrics, resolveResponsiveMetrics } from '../ui/ResponsiveMetrics';
import { BUTTON_RADIUS } from '../ui/UiConstants';

@Component
export struct ConfigurationPage {
  @State profiles: Profile[] = [];
  @State activeProfileId: string = '';
  @State stage: ProfileUpdateStage = ProfileUpdateStage.IDLE;
  @State busyProfileId: string = '';
  @State showProfileSheet: boolean = false;
  @State sheetMode: string = 'ADD';
  @State addName: string = '';
  @State addUrl: string = '';
  @State renameName: string = '';
  @State renameProfileId: string = '';
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribe: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribe = profileStore.subscribe((snapshot: ProfileStoreSnapshot): void => {
      this.profiles = snapshot.profiles;
      this.activeProfileId = snapshot.activeProfileId;
      this.stage = snapshot.stage;
      this.busyProfileId = snapshot.busyProfileId;
    });
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  private updateWidth(width: Length): void {
    const numericWidth = typeof width === 'number' ? width :
      (typeof width === 'string' ? Number(width) : 0);
    this.metrics = resolveResponsiveMetrics(Number.isFinite(numericWidth) ? numericWidth : 0);
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

  private openAddSubscription(): void {
    this.sheetMode = 'ADD';
    this.showProfileSheet = true;
  }

  private showAddOptions(): void {
    this.sheetMode = 'SOURCE';
    this.showProfileSheet = true;
  }

  private hasSubscription(): boolean {
    return this.profiles.some((profile: Profile): boolean => profile.type === ProfileType.SUBSCRIPTION);
  }

  private async selectProfile(id: string): Promise<void> {
    try {
      await profileStore.select(id);
      feedbackService.success('已切换活动配置');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private openRename(profile: Profile): void {
    this.renameProfileId = profile.id;
    this.renameName = profile.name;
    this.sheetMode = 'RENAME';
    this.showProfileSheet = true;
  }

  private async renameProfile(): Promise<void> {
    try {
      await profileStore.rename(this.renameProfileId, this.renameName);
      this.showProfileSheet = false;
      feedbackService.success('配置已重命名');
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

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : '配置操作失败';
  }

  private clearSheetInputs(): void {
    this.addName = '';
    this.addUrl = '';
    this.renameName = '';
    this.renameProfileId = '';
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
        return '正在替换配置';
      case ProfileUpdateStage.APPLIED:
        return '配置已替换';
      case ProfileUpdateStage.PERSISTING:
        return '正在保存元数据';
      default:
        return '';
    }
  }

  private formatUpdateTime(profile: Profile): string {
    if (profile.lastUpdateAt === undefined) {
      return '尚未更新';
    }
    return new Date(profile.lastUpdateAt).toLocaleString();
  }

  @Builder
  private pageHeader() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text($r('app.string.nav_configuration'))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.content_primary'))
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

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
          .visibility(this.busyProfileId.length > 0 ? Visibility.Visible : Visibility.Hidden)
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
    Column({ space: 14 }) {
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(profile.name)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(profile.type === ProfileType.LOCAL ? '本地 YAML' : getSubscriptionHost(profile.sourceUrl))
            .fontSize(13)
            .fontColor($r('app.color.content_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        if (profile.id === this.activeProfileId) {
          Text('当前')
            .fontSize(12)
            .fontColor($r('app.color.status_success'))
            .padding({ left: 9, right: 9, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor($r('app.color.status_success_surface'))
        }
      }
      .width('100%')

      Text(`更新：${this.formatUpdateTime(profile)}`)
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
        .width('100%')

      Row({ space: 8 }) {
        Button(profile.id === this.activeProfileId ? '已选择' : '选择')
          .type(ButtonType.Normal)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0 && profile.id !== this.activeProfileId)
          .onClick((): void => {
            this.selectProfile(profile.id);
          })
        Button('更新')
          .type(ButtonType.Normal)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0 && profile.type === ProfileType.SUBSCRIPTION)
          .onClick((): void => {
            this.updateProfile(profile.id);
          })
        Button('改名')
          .type(ButtonType.Normal)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0)
          .onClick((): void => {
            this.openRename(profile);
          })
        Button('删除')
          .type(ButtonType.Normal)
          .borderRadius(BUTTON_RADIUS)
          .fontColor($r('app.color.status_error'))
          .enabled(this.busyProfileId.length === 0)
          .onClick((): void => {
            this.confirmRemove(profile);
          })
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.metrics.profileCardWidth)
    .padding(18)
    .margin({ bottom: this.metrics.cardGap })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
    .border({
      width: profile.id === this.activeProfileId ? 2 : 0,
      color: $r('app.color.nav_selected')
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
        .textAlign(TextAlign.Start)
      Text('使用右下角的添加按钮选择订阅或本地 YAML。')
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
    }
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(24)
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private addProfileSheet() {
    Column({ space: 18 }) {
      Row() {
        Text('添加订阅')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.content_primary'))
          .width('100%')
      }
      .width('100%')
      TextInput({ placeholder: '配置名称', text: this.addName })
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
      Text('完整订阅地址仅保存在应用私有数据库，不会显示在卡片或写入日志。')
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
        .enabled(this.busyProfileId.length === 0)
        .onClick((): void => {
          this.addSubscription();
        })
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(24)
  }

  @Builder
  private renameSheet() {
    Column({ space: 18 }) {
      Text('重命名配置')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.content_primary'))
        .width('100%')
      TextInput({ placeholder: '配置名称', text: this.renameName })
        .width('100%')
        .onChange((value: string): void => {
          this.renameName = value;
        })
      Row({ space: 12 }) {
        Button('取消')
          .layoutWeight(1)
          .type(ButtonType.Normal)
          .borderRadius(BUTTON_RADIUS)
          .onClick((): void => {
            this.showProfileSheet = false;
          })
        Button('保存')
          .layoutWeight(1)
          .type(ButtonType.Normal)
          .borderRadius(BUTTON_RADIUS)
          .enabled(this.busyProfileId.length === 0)
          .onClick((): void => {
            this.renameProfile();
          })
      }
      .width('100%')
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
    if (this.sheetMode === 'RENAME') {
      this.renameSheet()
    } else if (this.sheetMode === 'SOURCE') {
      this.addSourceSheet()
    } else {
      this.addProfileSheet()
    }
  }

  @Builder
  private floatingAddButton() {
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
      .zIndex(2)
      .onClick((): void => {
        this.showAddOptions();
      })
  }

  build() {
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
        .justifyContent(FlexAlign.Start)
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
      this.floatingAddButton()
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
