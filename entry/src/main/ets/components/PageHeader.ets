import { CAPTION_FONT_SIZE, PAGE_TITLE_SIZE } from '../constants/UiConstants';

@Component
export struct PageHeader {
  @Prop title: ResourceStr = '';
  @Prop subtitle: ResourceStr = '';
  @BuilderParam actions: () => void = this.emptyActions;

  @Builder
  private emptyActions() {
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(PAGE_TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.content_primary'))
          .width('100%')
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(CAPTION_FONT_SIZE)
            .fontColor($r('app.color.content_secondary'))
            .width('100%')
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      this.actions()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }
}
