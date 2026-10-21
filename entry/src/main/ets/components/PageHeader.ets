import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { CAPTION_FONT_SIZE, HEADER_CONTENT_HEIGHT, PAGE_TITLE_SIZE } from '../constants/UiConstants';

/** 统一一级页面标题区域，操作区由调用方通过 Builder 注入。 */
@Component
export struct PageHeader {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop title: ResourceStr = '';
  @Prop subtitle: ResourceStr = '';
  @Prop subtitleColor: ResourceColor = $r('app.color.content_secondary');
  @Prop contentPadding: number = 16;
  @BuilderParam actions: () => void = this.emptyActions;

  @Builder
  private emptyActions() {
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(themeFontSize(PAGE_TITLE_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.content_primary'))
          .width('100%')
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor(this.subtitleColor)
            .width('100%')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .constraintSize({ minHeight: HEADER_CONTENT_HEIGHT })
      .layoutWeight(1)
      this.actions()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: this.contentPadding, left: this.contentPadding, right: this.contentPadding })
  }
}
