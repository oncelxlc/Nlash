import { CAPTION_FONT_SIZE } from '../constants/UiConstants';

/** 规则和代理链直接可见，长节点名换行，避免挤压目标地址。 */
@Component
export struct ConnectionRoute {
  @Prop rule: string = '';
  @Prop payload: string = '';
  @Prop chains: string[] = [];

  build() {
    Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
      Text(this.payload.length > 0 ? `${this.rule}(${this.payload})` : (this.rule || '规则未报告'))
        .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
        .margin({ right: 8, bottom: 4 })
      ForEach(this.chains, (chain: string, index: number) => {
        Text('→').fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
          .margin({ right: 8, bottom: 4 }).accessibilityLevel('no')
        Text(chain).fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_primary'))
          .padding({ left: 8, right: 8, top: 3, bottom: 3 })
          .borderRadius(12).backgroundColor($r('app.color.surface_muted'))
          .margin({ right: 8, bottom: 4 }).wordBreak(WordBreak.BREAK_ALL)
      }, (chain: string, index: number): string => `${index}:${chain}`)
    }
    .width('100%')
  }
}
