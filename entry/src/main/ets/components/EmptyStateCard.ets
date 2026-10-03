import {
  CARD_RADIUS, BODY_FONT_SIZE
} from '../constants/UiConstants';
@Component
export struct EmptyStateCard {
  @Prop title: ResourceStr = '';
  @Prop description: ResourceStr = '';

  build() {
    Column({ space: 10 }) {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.content_primary'))
      Text(this.description)
        .fontSize(BODY_FONT_SIZE)
        .fontColor($r('app.color.content_secondary'))
        .textAlign(TextAlign.Start)
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(24)
    .borderRadius(CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
  }
}
