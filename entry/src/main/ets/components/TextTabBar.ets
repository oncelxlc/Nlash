/** 统一代理组和活动页的二级文字标签样式。 */
export function textTabBar(label: ResourceStr): SubTabBarStyle {
  return new SubTabBarStyle(label)
    .indicator({ color: $r('app.color.nav_selected'), height: 2, borderRadius: 1 })
    .labelStyle({
      selectedColor: $r('app.color.nav_selected'),
      unselectedColor: $r('app.color.content_secondary'),
      font: { size: 14, weight: FontWeight.Medium }
    })
    .padding({ left: 12, right: 12, top: 0, bottom: 0 });
}
