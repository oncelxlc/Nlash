import { AppTheme } from '../model/ThemeModels';
import { themeFontSize } from '../utils/ThemeUtils';

@Builder
function menuItemContent(item: MenuElement, theme: AppTheme) {
  Row({ space: 12 }) {
    if (item.icon !== undefined) {
      Image(item.icon).width(20).height(20).fillColor($r('app.color.content_primary')).accessibilityLevel('no')
    }
    Text(item.value).fontSize(themeFontSize(16, theme)).fontFamily(theme.fontFamily)
      .fontColor($r('app.color.content_primary')).layoutWeight(1).maxLines(3)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }.width('100%').padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .opacity(item.enabled === false ? 0.4 : 1)
}

/** 保留原菜单动作和禁用状态，让菜单文字采用应用字体及缩放。 */
@Builder
export function themeMenu(items: MenuElement[], theme: AppTheme) {
  Menu() {
    ForEach(items, (item: MenuElement) => {
      MenuItem(menuItemContent(item, theme)).enabled(item.enabled !== false)
        .onClick(item.action)
    })
  }.width(theme.fontScale > 1.2 ? 320 : 240).backgroundColor(theme.surface)
}
