import { CAPTION_FONT_SIZE, HEADER_CONTENT_HEIGHT, PAGE_TITLE_SIZE } from '../constants/UiConstants';

@Component
export struct PageHeader {
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
          .fontSize(PAGE_TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.content_primary'))
          .width('100%')
        if (this.subtitle !== '') {
          Text(this.subtitle)
            .fontSize(CAPTION_FONT_SIZE)
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
