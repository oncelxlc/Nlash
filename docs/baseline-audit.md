# Nlash 基线审计

审计日期：2026-08-28

## 工程状态

- 工程由 `entry` HAP 模块和 `proxy_core` Native HAR 模块组成，没有重新初始化工程。
- `EntryAbility` 初始化现有状态存储；`ProxyVpnAbility` 创建 IPv4 TUN 并把 FD 交给 Native Core。
- `VpnService` 使用显式状态枚举及 `startOperation` / `stopOperation` Promise 串行化。
- Native 桥已提供配置校验、Core 生命周期、运行时命令和脱敏事件接口，并链接固定版本的 Mihomo Core。
- `entry/src/test` 已有导航测试；历史 `AGENTS.md` 中“没有测试文件”的描述不准确。

## 工具链

| 项目 | 当前值 |
|---|---|
| DevEco Studio | 6.1.1.300 |
| HarmonyOS target / compatible SDK | 6.1.1 (API 24) |
| Hvigor | 6.24.4 |
| Go | 1.27.0 windows/amd64 |
| 目标 ABI | arm64-v8a |

正确设置 `DEVECO_SDK_HOME` 后，基线 `assembleHap` 成功。首次 `hvigor test` 因 `proxy_core/src/test/List.test.ets` 缺失失败，本阶段补齐入口后重新验证。

## UI 差距

- 普通非折叠设备目前会根据宽度进入 Side 导航，不符合移动端新规则。
- Bottom 布局会把 Requests/Connections 强制重置到 Dashboard，无法保留当前一级页面。
- `Index.ets` 通过根级 `if/else` 切换 Side/Bottom 结构，尚无共享 `NavPathStack`。
- Dashboard 卡片使用固定 `maxWidth: 560` 居中，折叠内屏无法充分利用宽度。

## VPN 与 Native 差距

- 已能创建 TUN，并由 Mihomo Core 通过外部 FD 和 gVisor 栈处理转发。
- 每个出站 socket 都通过 Protect Channel 调用 `VpnConnection.protect(fd)`，避免流量回环。
- 固定 Go 工具链使用 OHOS clang/musl 构建 `linux/arm64` c-shared 产物，并校验 TLS relocation 模型。

## 当前验证边界

审计时 `hdc list targets` 没有连接设备，因此以下项目均未验证：HAP 安装、VPN 授权、TUN 真机收发、process socket protect、HTTP/HTTPS/DNS/TCP/UDP、折叠展开和后台生命周期。它们不得标记为完成。

后续验证检测到一台 HUAWEI Mate X6 典藏版（ICL-AL20，API 24），unsigned HAP 曾被设备以 `no signature file` 拒绝；该变化不改变本节的基线时点。

## 2026-08-28 实施更新

以上“工程状态”和“差距”保留为审计时点记录。当前实现已接入固定 Mihomo v1.19.30、外部 TUN FD、逐 socket `VpnConnection.protect(fd)`、LocalSocket framing、异步 Core Bridge、UI/Extension 跨进程状态通道和单次恢复；最终路径已移除 `protectProcessNet()`。本地测试、unsigned/signed HAP 构建及 Mate X6 最小验证已通过，完整真机流量与普通手机兼容性仍需发布前补测。
