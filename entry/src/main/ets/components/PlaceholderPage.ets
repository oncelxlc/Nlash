@Component
export struct PlaceholderPage {
  @Prop pageTitle: Resource;

  build() {
    Column({ space: 12 }) {
      Text(this.pageTitle)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.content_primary'))
      Text($r('app.string.feature_coming_soon'))
        .fontSize(16)
        .fontColor($r('app.color.content_secondary'))
    }
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor($r('app.color.app_background'))
  }
}
