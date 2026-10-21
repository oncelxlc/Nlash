import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { CAPTION_FONT_SIZE } from '../constants/UiConstants';

/** 通用状态标签，error 优先于 active，颜色从主题资源读取。 */
@Component
export struct StatusBadge {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop text: ResourceStr = '';
  @Prop active: boolean = false;
  @Prop error: boolean = false;

  build() {
    Text(this.text)
      .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.error ? $r('app.color.status_error') :
        (this.active ? $r('app.color.status_success') : $r('app.color.content_secondary')))
      .backgroundColor(this.error ? $r('app.color.status_error_surface') :
        (this.active ? $r('app.color.status_success_surface') : this.theme.muted))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(6)
  }
}
