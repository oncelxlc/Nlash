import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { CONTROL_HEIGHT } from '../constants/UiConstants';

/** 二级页面保持统一的返回触点和标题，右侧由页面提供操作。 */
@Component
export struct SecondaryPageHeader {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop title: string = '';
  @Prop contentPadding: number = 16;
  onBack: () => void = (): void => {};
  @BuilderParam actions: () => void = this.emptyActions;

  @Builder
  private emptyActions() {}

  build() {
    Row({ space: 16 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.action_back')).width(24).height(24)
          .fillColor($r('app.color.content_primary')).accessibilityLevel('no')
      }
      .id('settings-detail-back')
      .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).padding(0)
      .backgroundColor(this.theme.surface)
      .accessibilityText('返回设置')
      .onClick((): void => { this.onBack(); })
      Text(this.title).fontSize(themeFontSize(22, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary')).layoutWeight(1)
      this.actions()
    }
    .width('100%')
    .padding({ top: 16, bottom: 16, left: this.contentPadding, right: this.contentPadding })
  }
}
