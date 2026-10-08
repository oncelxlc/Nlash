import { EmptyStateBackground } from './EmptyStateBackground';
import { PageHeader } from './PageHeader';

@Component
export struct PlaceholderPage {
  @Prop pageTitle: Resource;

  build() {
    Column({ space: 12 }) {
      PageHeader({ title: this.pageTitle })
      Stack() {
        EmptyStateBackground({ title: $r('app.string.feature_coming_soon') })
      }
      .width('100%').layoutWeight(1)
    }
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding(24)
    .backgroundColor($r('app.color.app_background'))
  }
}
