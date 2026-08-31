# entry 目录与职责整理验收

日期：2026-08-31。完成目录迁移和职责拆分，不改业务状态管理、路由、持久化格式或 Native ABI；未新增依赖和 ViewModel 层。

## 修改范围

| 分类 | 调整 |
|---|---|
| 页面与业务视图 | 保留 pages/Index；DashboardPage、ConfigurationPage、ProxyPage、RequestsPage、ConnectionsPage、SettingsPage、NavigationBasePage 从 components 迁入 view |
| 仪表盘卡片 | RuntimeSpeedCard、RuntimeTrafficCard、RuntimeStatusCard 分别拆为 view 下独立文件，属性、Canvas 绘制和更新逻辑保持原样 |
| 公共组件 | components 保留 PlaceholderPage；新增 EmptyStateCard，仅接收 title、description，复用请求/连接双文本空状态的原布局 |
| 模型与常量 | models 改为 model；保留领域类型名称，将共享常量和默认值移至 constants；CoreControlProtocol 的类型与常量分别归入 CoreControlModels/CoreControlConstants |
| 工具 | 领域函数与算法辅助类原样移至 utils；响应式类型、配置、计算分离；六页共用 resolveContentWidth，请求/连接共用 formatLocalTime |
| 调用与测试 | 同步所有生产和测试导入，保留已有测试主体，新增 UiUtils.test.ets 的三项回归并注册至 List.test.ets |
| 文档与规划 | 更新 AGENTS.md 的目录和页面注册指引；task_plan.md、findings.md、progress.md 追加本次记录，保留历史通知任务的锁屏阻塞 |

服务、Store、仓储、Ability、导航文件只改导入。原 ui/models 目录已移除，不保留转导出兼容层。build-profile.json5 的用户已有修改未触碰。

## 自动验证

- 与实施前源码快照逐声明比对：139 个类型、常量、函数及辅助类保持原样；响应式配置仅增加跨文件所需的 export。
- 26 个服务、Store、Ability、导航和入口页面主体一致，三个拆出的仪表盘组件主体一致。
- 82 个源码/测试文件的相对导入和命名导出可解析，无循环依赖；model 无反向依赖，源码无旧目录导入。
- 所有既有测试主体保持原样；git diff --check 通过。

| 验证 | 结果 |
|---|---|
| 规划阶段基线 | entry 64/64、proxy_core 1/1 |
| hvigor test --no-daemon | entry 67/67、proxy_core 1/1；实际 test_result.txt 均为 Failure=0、Error=0 |
| 新增回归 | 数字/字符串/Resource 宽度转换、非有限值回退、640/900 断点、强制展开、时间格式化和非正时间戳 |
| hvigor assembleHap --no-daemon | 成功生成 entry/build/default/outputs/default/entry-default-signed.hap |

使用 DevEco 自带 Node/Hvigor，按测试、打包的顺序执行；工具缓存读取通过权限流程运行。新增测试首次缺少 Resource 的 bundleName/moduleName，补齐后通过。保留已有 ArkTS、资源和弃用 API 警告，不扩大修复范围。

## 真机检查

已通过 HDC 保留数据更新签名 HAP，成功启动 EntryAbility；未修改、更新或删除订阅，也未修改主题或网络设置。

| 场景 | 结果 |
|---|---|
| 仪表盘、代理、配置、设置页面切换 | 通过；内容正常加载 |
| 配置编辑器返回 | 打开编辑器后按返回，回到配置页；未保存任何修改 |
| 设置页返回 | 回到仪表盘，正常显示状态 |
| 仪表盘三个拆分卡片 | 截图确认布局正常；VPN 开启后曲线、流量统计、活动连接数量更新 |
| VPN 开启/关闭 | 开启后 UI 提示成功、计时增长、/proc/net/dev 出现 vpn-tun；关闭后提示成功、vpn-tun 消失，下一次 UI 刷新恢复关闭状态 |

截图仅保存在忽略的 entry/.test/entry-restructure-qa 下，没有纳入源码。结束时代理保持关闭。

## 尚未覆盖

当前真机显示底部导航，未实际展开设备，因此侧栏专属请求/连接页面、两页的公共空状态及折叠/展开/小窗口切换未完成交互验收；这些代码已通过静态检查和应用编译，响应式逻辑已通过单元测试。尚需在展开设备上检查侧栏六页、空状态和布局切换。

本次未执行长时间后台/锁屏验收，不处理或宣称修复历史通知任务中的锁屏退出问题。
