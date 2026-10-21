import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { CAPTION_FONT_SIZE } from '../constants/UiConstants';

/** 规则和代理链直接可见，长节点名换行，避免挤压目标地址。 */
@Component
export struct ConnectionRoute {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop rule: string = '';
  @Prop payload: string = '';
  @Prop chains: string[] = [];

  build() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text(this.payload.length > 0 ? `${this.rule}(${this.payload})` : (this.rule || '规则未报告'))
        .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
        .margin({ right: 8, bottom: 4 })
      ForEach(this.chains, (chain: string, index: number) => {
        Text('→').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
          .margin({ right: 8, bottom: 4 }).accessibilityLevel('no')
        Text(chain).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_primary'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(12).backgroundColor(this.theme.muted)
          .margin({ right: 8, bottom: 4 }).wordBreak(WordBreak.BREAK_ALL)
      }, (chain: string, index: number): string => `${index}:${chain}`)
    }
    .width('100%')
  }
}
