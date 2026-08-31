# 本地构建与测试

## 工具链

当前工程使用 DevEco Studio 6.1.1.300 自带的 HarmonyOS SDK 与 Hvigor。Windows PowerShell 示例：

```powershell
$env:DEVECO_SDK_HOME = 'E:\Program Files\Huawei\DevEco Studio\sdk'
$hvigor = 'E:\Program Files\Huawei\DevEco Studio\tools\hvigor\bin\hvigorw.bat'
$ohpm = 'E:\Program Files\Huawei\DevEco Studio\tools\ohpm\bin\ohpm.bat'

& $ohpm install
& .\native-core\build-ohos.ps1
& $hvigor assembleHap --no-daemon
& $hvigor test --no-daemon
```

不要把 SDK 路径写入受版本控制的 `local.properties`。不同安装位置应仅调整当前终端环境变量。

## 签名

仓库默认不包含签名材料；未配置本地签名时命令行构建生成 unsigned HAP。需要安装到真机时，可在本地 DevEco Studio 配置签名并生成 signed HAP；不得提交证书、profile、keystore、口令或机器绝对路径。

历史版本曾提交机器绑定的调试签名配置。相关凭据必须在开发者账号侧轮换，单纯从当前文件删除不能清除 Git 历史。

## 真机测试

连接设备后先确认：

```powershell
& 'E:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' list targets
```

`ohosTest`、VPN 授权、TUN、socket protect、网络切换及折叠屏状态只能以真机结果验收。

### 返回桌面回归检查

- 从其他一级页面返回，应先回到仪表盘；配置编辑器仍优先处理自己的返回操作。
- 在仪表盘返回，应切到后台，日志出现 `Ability onBackground`，不应因该操作出现 `Ability onDestroy`。
- 再次打开应用，应恢复界面，日志出现 `Ability onForeground`，不应重新执行 `Ability onCreate`（系统未回收进程时）。
- 开启代理后，分别通过返回手势、系统桌面手势切到后台，确认 VPN 连接与代理流量保持正常；回到应用后仍可主动停止代理。

返回操作使用系统后台切换接口，VPN 继续由已有 `VpnExtensionAbility` 承载；不保证强行停止应用或系统回收后的进程常驻。

2026-08-28 的真机轮次已完成签名校验、Mate X6 安装、Native 冷启动 20/20、TUN 创建销毁 20/20 和 UI/Extension 跨进程状态同步。完整代理流量、网络切换和普通手机兼容性仍需按发布验收矩阵补测。
