import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME } from '../utils/ThemeUtils';
import { EmptyStateBackground } from './EmptyStateBackground';
import { PageHeader } from './PageHeader';

/** 为尚未实现的页面复用统一标题与空态布局。 */
@Component
export struct PlaceholderPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
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
    .backgroundColor(this.theme.background)
  }
}
