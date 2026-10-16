import { EmptyStateBackground } from './EmptyStateBackground';
import { PageHeader } from './PageHeader';

@Component
export struct PlaceholderPage {
  @Prop pageTitle: Resource;

  build() {
    Column({ space: 12 }) {
      PageHeader({ title: this.pageTitle, contentPadding: 24 })
      Stack() {
        EmptyStateBackground({ title: $r('app.string.feature_coming_soon') })
      }
      .width('100%').layoutWeight(1)
      .padding({ left: 24, right: 24, bottom: 24 })
    }
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
  }
}
