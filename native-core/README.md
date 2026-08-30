# Nlash Native Core

该目录将固定的 Mihomo v1.19.30 以 Go `linux/arm64` c-shared 形式链接到 HarmonyOS，并导出配置校验、启动、停止、状态和脱敏事件 ABI。运行时强制使用外部 TUN FD、gVisor 栈并关闭 Mihomo 自身的路由管理。

版本固定在 `VERSION`。在仓库根目录执行：

```powershell
$env:DEVECO_SDK_HOME = 'E:\Program Files\Huawei\DevEco Studio\sdk'
& .\native-core\build-ohos.ps1
```

输出位于 `native-core/out/arm64-v8a/`，并同步到 `proxy_core/src/main/cpp/prebuilt/arm64-v8a/` 供 HAP 链接。脚本会校验 Go 版本、Mihomo tag/module checksum、固定 commit 元数据与 API 24，并先运行 `CGO_ENABLED=0 go test .`。

HarmonyOS 使用 musl loader，而 Go 1.27.0 的默认 ARM64 c-shared 产物使用 Initial Exec TLS，不能由 N-API 通过 `dlopen()` 加载。首次构建会在 `.toolchains/go1.27.0-tlsgd` 创建固定 Go 1.27.0 的本地副本，并应用 `toolchain-patches/go1.27-musl-arm64-tlsgd.patch`。该补丁回移自 Go 官方评审 `97ce7c6e...`，只修改本地副本，不修改系统 Go。构建脚本要求最终 ELF 包含 `R_AARCH64_TLSDESC` 且不包含 `R_AARCH64_TLS_TPREL`。

构建成功只说明工具链与链接器接受产物，不代表真实代理流量 Gate 已通过。

该 HAP 当前仅用于用户自有设备的内部技术验证。Mihomo 使用 GPL-3.0；任何对外分发、商店发布或正式产品化必须先完成独立许可证合规评审和相应源代码义务。

脚本会在 `native-core/.ohos-native` 创建一个被 Git 忽略的 Windows 目录联接，以绕过 Go CGO 对含空格 SDK 路径的参数拆分问题；联接目标仍是本机 DevEco SDK，不会复制或修改 SDK。
