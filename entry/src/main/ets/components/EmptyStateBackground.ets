import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import {
  BODY_FONT_SIZE, CAPTION_FONT_SIZE, FLOATING_NAVIGATION_INSET
} from '../constants/UiConstants';

/** 可复用空态背景；compact 用于卡片内展示，组件不拦截底层交互。 */
@Component
export struct EmptyStateBackground {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop title: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop icon: Resource = $r('app.media.nav_activity');
  @Prop compact: boolean = false;

  build() {
    Column({ space: 12 }) {
      if (!this.compact) {
        Image(this.icon)
          .width(72).height(72)
          .fillColor($r('app.color.content_secondary'))
          .opacity(0.18)
          .blur(3)
          .accessibilityLevel('no')
      }
      Text(this.title)
        .fontSize(themeFontSize(this.compact ? CAPTION_FONT_SIZE : BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
        .fontColor($r('app.color.content_secondary'))
        .textAlign(TextAlign.Center)
        .width('100%')
      if (this.description !== '') {
        Text(this.description)
          .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_secondary'))
          .textAlign(TextAlign.Center)
          .lineHeight(20)
          .constraintSize({ maxWidth: 280 })
          .width('100%')
      }
    }
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: this.compact ? 0 : FLOATING_NAVIGATION_INSET })
    .hitTestBehavior(HitTestMode.None)
    .accessibilityGroup(true)
  }
}
