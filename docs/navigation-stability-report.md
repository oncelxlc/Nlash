# 导航稳定性验证报告

## 实现范围

- 导航布局只由“是否折叠屏”和“是否展开”决定：普通手机与折回外屏使用 Bottom，展开内屏使用 Side。
- Side、ContentHost、Bottom 固定在同一个组件树内，布局切换只改变可见性与占用尺寸。
- `Index` 只创建一个 `AppNavigationState` 和一个 `NavPathStack`；一级 Tab 切换会清空二级路由，折叠状态变化不会重建路由栈。
- `Requests` / `Connections` 在 Bottom 布局中虽无一级入口，但当前页面不会被强制改回 Dashboard。
- Dashboard 已移除 560 vp 最大宽度限制，可填满外屏与内屏内容区。

## 自动验证

| 项目 | 结果 | 说明 |
|---|---|---|
| ArkTS 编译 | 通过 | `hvigor assembleHap --no-daemon`，unsigned HAP |
| ArkTS 单测 | 通过 | `hvigor test --no-daemon` |
| 普通手机布局解析 | 通过 | 无论展开标记如何均返回 Bottom |
| 折叠屏布局解析 | 通过 | 折回 Bottom，展开 Side |
| 隐藏入口保留 | 通过 | Bottom 下保留 Requests / Connections |
| 深浅色资源完整性 | 通过 | AppShell、Navigation、NavDestination、Skeleton 均使用语义色资源 |

## 真机验证矩阵

已检测到一台 HUAWEI Mate X6 典藏版折叠屏（API 24），但 unsigned HAP 被设备拒绝安装；普通手机尚未连接。以下项目不得以编译或 Mock 代替，状态均为 **待签名/待验证**：

| 设备/场景 | 状态 | 需要采集的证据 |
|---|---|---|
| 普通手机冷启动与一级切换 | 待验证 | 录屏与设备/系统版本 |
| 折叠屏外屏冷启动 | 待验证 | Bottom 导航录屏 |
| 展开内屏且停留一级页面 | 待验证 | 无白闪、Side 导航录屏 |
| Requests / Connections 中折回外屏 | 待验证 | 隐藏入口页面继续显示录屏 |
| 深色模式启动及切屏 | 待验证 | 首帧与转场无白闪录屏 |

## 结论

阶段 1 的代码、构建和单元测试已完成；涉及无闪动、路由栈实际返回行为和折叠屏切屏的验收受本地签名与普通手机缺失阻塞。未补齐双设备证据前不视为产品验收通过。
