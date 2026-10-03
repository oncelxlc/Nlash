# Core 生命周期与配色布局回归记录

日期：2026-10-03。

## 实现

- `EntryAbility` 在创建时启动或连接 Core 宿主；新宿主先加载关闭监听端口、DNS 和 TUN 的基础配置，再热加载活动配置。已有宿主复用状态。未成功应用用户配置时不能开启代理。
- `VpnService`、`ProxyVpnAbility` 和 Go runtime 分离配置热加载、代理开关及完整重启。内部新增 `applyConfig` / `rollbackConfig` 命令，复用现有 N-API/C ABI；保留有效配置原文、TUN 设置及 socket protect。配置应用成功后提交活动选择；失败保留或恢复之前的运行配置。热加载不发布 Core 停机状态。
- 会话起止时间由 VPN 宿主使用包含休眠时间的单调时钟维护，通过生命周期快照及事件同步。临时重启恢复连续计时，关闭后冻结，下次连接成功重新开始；不持久化使用历史。
- 概览右上角状态按钮可重启 Core，代理开启时先确认；右下角浮动按钮只控制代理。滚动区为浮动控件及导航栏留出空间。
- 浅深主题采用黑白灰，新增 `action_primary` 资源区分主操作与导航选中态。设置页使用分段 WaterFlow，640vp 以下单列，其余双列；以实测列宽约束卡片，防止百分比内容越列，按自然高度排列。
- 每次建立 VPN 前重新读取 UI 进程已保存的网络设置，MTU 在下次连接生效。x86_64 模拟器明确显示当前架构不支持 Mihomo Core，不伪造运行状态。

未增加依赖，Mihomo 仍固定 v1.19.30；保留已有本地构建配置修改，未创建分支、提交或推送。

## 自动验证

| 项目 | 结果 |
|---|---|
| 固定工具链 `go test -mod=readonly .`，CGO 关闭 | 通过；覆盖基础启动、热加载、同路径非法覆盖与回退、节点/模式不触发 Core 停启、TUN 参数保留 |
| `native-core/build-ohos.ps1` | 通过，ARM64 库已同步；TLSDESC 存在、TPREL 不存在 |
| 原生库打包链路 | 构建输出、预编译库、打包输入哈希一致；strip 前后 ELF build notes 一致，HAP 内库与 strip 产物一致 |
| `hvigorw.bat test --no-daemon` | entry 66/66、proxy_core 1/1；Failure=0、Error=0、Ignore=0 |
| 新增 ArkTS 回归 | 启动并发去重、失败后重试、跨进程时间字段、迟到事件、连续计时、停止冻结及重新开始 |
| `hvigorw.bat assembleHap --no-daemon` | 通过，生成 signed/unsigned HAP |
| 格式与资源 | Go 文件符合 gofmt；JSON 资源无重名；`git diff --check` 通过 |
| 配色对比度 | 已检查文字组合最低：浅色 4.60:1、深色 4.90:1；输入控件边界至少 3:1 |

Hvigor 的 test 与 assembleHap 分开顺序执行，避免多目标共享 loader 中间目录导致冲突。构建仍有原有异常处理、弃用 API 和工具链告警，未关闭检查规则。

测试明细位于 `entry/.test/default/intermediates/test/coverage_data/test_result.txt` 和 `proxy_core/.test/default/intermediates/test/coverage_data/test_result.txt`。

## 模拟器验证与限制

- 已在两台 API 24、x86_64 模拟器安装最终 signed HAP，检查约 366vp 手机、717vp 宽屏及约 921vp 横屏特大字号的概览和设置布局，浅深主题、选中态、导航与滚动避让正常。
- 旋转后未保存的网络输入保留；非法 MTU 产生行内错误并撑开卡片；关于卡片可滚动至导航上方。测试未保存非法网络设置。
- 测试结束恢复标准字体、默认显示缩放、竖屏和应用跟随系统主题。
- 截图及 UI 树保存在 Git 忽略的 `entry/.test/core-ui-qa/`；最终设置页为 `final-settings-wide.png`、`final-settings-phone.png`，大字号记录为 `wide-settings-large.png`。
- 没有完成 320/640/900vp 三个精确尺寸的逐项截图；640/900vp 逻辑边界由已有单测覆盖。
- 当前无 ARM 真机。VPN 授权、真实 TUN/socket protect、实际代理流量中的配置热切换、Core 重启后代理恢复，以及 UI 进程重建后的实际跨进程计时，仍需真机验收。模拟器的架构不可用提示是预期结果。

最终安装包：`entry/build/default/outputs/default/entry-default-signed.hap`。
