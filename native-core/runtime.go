package main

import (
	"context"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/mmdb"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	coreLog "github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

// coreRuntimeState 的数值属于跨语言 ABI，须与 C++ 枚举和 ArkTS 映射顺序一致。
type coreRuntimeState int32

const (
	coreStopped coreRuntimeState = iota
	coreValidating
	coreStarting
	coreRunning
	coreStopping
	coreFailed
)

// coreErrorCode 通过 C ABI 返回；错误描述由 lastError 单独传递。
type coreErrorCode int32

const (
	coreOK coreErrorCode = iota
	coreInvalidArgument
	coreInvalidState
	coreConfigInvalid
	coreProtectFailed
	coreStartFailed
	coreStopFailed
	coreInternalError
)

type coreStartOptions struct {
	configPath string
	workDir    string
}

// coreProxyOptions 接收宿主提供的 TUN 副本和本轮 protect 通道标识。
type coreProxyOptions struct {
	tunFD             int
	mtu               int
	protectSocketPath string
	generation        string
}

/*
coreRuntime 管理进程内唯一的 Mihomo 实例，mu 串行保护配置和生命周期变更。
Core 运行与系统代理启用是独立状态；配置字节保留在内存中，供重载失败时恢复。
*/
type coreRuntime struct {
	mu                 sync.RWMutex
	state              coreRuntimeState
	lastError          string
	protect            *protectClient
	configPath         string
	configData         []byte
	previousConfigPath string
	previousConfigData []byte
	workDir            string
	proxyEnabled       bool
	proxyGroupOrder    []string
	geoUpdating        atomic.Bool
	geoGeneration      uint64
	geoContext         context.Context
	geoCancel          context.CancelFunc
	geoTimer           *time.Timer
	general            generalSettings
	systemDNS          []string
}

var runtimeInstance = &coreRuntime{state: coreStopped}

// 拨号线程只读取原子指针，避免等待持有 mu 的启动、重载或停止操作。
var activeSocketProtect atomic.Pointer[protectClient]

func init() {
	// Keep the hook stable while delay requests and proxy lifecycle operations overlap.
	dialer.DefaultSocketHook = func(_ string, _ string, connection syscall.RawConn) error {
		if protect := activeSocketProtect.Load(); protect != nil {
			return protectSocket(protect, connection)
		}
		return nil
	}
}

func (runtime *coreRuntime) getState() coreRuntimeState {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.state
}

func (runtime *coreRuntime) getLastError() string {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.lastError
}

// setFailure 在调用方持有写锁时进入失败状态；reject 只拒绝当前操作。
func (runtime *coreRuntime) setFailure(code coreErrorCode, err error) coreErrorCode {
	runtime.state = coreFailed
	runtime.lastError = sanitizeCoreError(err)
	emitCoreEvent(coreEventLifecycle, runtime.state, code, runtime.lastError)
	return code
}

func (runtime *coreRuntime) reject(code coreErrorCode, err error) coreErrorCode {
	runtime.lastError = sanitizeCoreError(err)
	return code
}

// validate 会设置 Mihomo 的全局配置路径，因此仅允许在 Core 未运行时执行。
func (runtime *coreRuntime) validate(configPath string) coreErrorCode {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state != coreStopped && runtime.state != coreFailed {
		return runtime.reject(coreInvalidState, errors.New("core is busy"))
	}
	runtime.state = coreValidating
	runtime.lastError = ""
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "validating configuration")
	if configPath == "" {
		return runtime.setFailure(coreInvalidArgument, errors.New("configuration path is empty"))
	}
	homeDir, err := prepareConfigHome(configPath)
	if err != nil {
		return runtime.setFailure(coreConfigInvalid, err)
	}
	C.SetHomeDir(homeDir)
	C.SetConfig(configPath)
	if _, err := parseConfigWithPath(configPath); err != nil {
		return runtime.setFailure(coreConfigInvalid, err)
	}
	runtime.state = coreStopped
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "configuration is valid")
	return coreOK
}

// start 先启动不接管系统流量的 Core，TUN 由后续 enableProxy 单独接入。
func (runtime *coreRuntime) start(options coreStartOptions) (code coreErrorCode) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state != coreStopped && runtime.state != coreFailed {
		return runtime.reject(coreInvalidState, errors.New("core is already active"))
	}
	runtime.state = coreStarting
	dnsHistory.clear()
	runtime.lastError = ""
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "starting core")
	if options.configPath == "" || options.workDir == "" {
		return runtime.setFailure(coreInvalidArgument, errors.New("core start options are invalid"))
	}
	if err := os.MkdirAll(options.workDir, 0700); err != nil {
		return runtime.setFailure(coreStartFailed, err)
	}
	runtime.workDir = options.workDir

	defer func() {
		if recovered := recover(); recovered != nil {
			code = runtime.setFailure(coreInternalError, fmt.Errorf("mihomo start panic: %v", recovered))
		}
	}()
	C.SetHomeDir(options.workDir)
	C.SetConfig(options.configPath)
	// 上轮停止后重新读取已更新文件，旧映射由 Reader 的 finalizer 回收。
	mmdb.ReloadIP()
	mmdb.ReloadASN()
	geodata.ClearGeoIPCache()
	geodata.ClearGeoSiteCache()
	data, err := os.ReadFile(options.configPath)
	if err != nil {
		return runtime.setFailure(coreConfigInvalid, err)
	}
	settings, err := readGeneralSettings(options.workDir)
	if err != nil {
		return runtime.setFailure(coreConfigInvalid, err)
	}
	cfg, proxyGroupOrder, err := parseRuntimeConfigWithSettings(data, false, settings, runtime.systemDNS)
	if err != nil {
		return runtime.setFailure(coreConfigInvalid, err)
	}
	configureHarmonyCore(cfg)
	if runtime.protect != nil {
		runtime.protect.close()
	}
	runtime.protect = nil
	runtime.proxyEnabled = false
	activeSocketProtect.Store(nil)
	if err := applyRuntimeConfig(cfg); err != nil {
		executor.Shutdown()
		_ = applyController("", "")
		return runtime.setFailure(coreStartFailed, err)
	}
	runtime.configPath = options.configPath
	runtime.configData = data
	runtime.previousConfigPath = ""
	runtime.previousConfigData = nil
	runtime.workDir = options.workDir
	runtime.general = settings
	runtime.proxyGroupOrder = proxyGroupOrder
	runtime.state = coreRunning
	runtime.scheduleGeoUpdates()
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "core is running")
	return coreOK
}

// applyConfig keeps the running core, platform TUN and socket protection in place.
func (runtime *coreRuntime) applyConfig(configPath string, rollback bool) coreCommandResponse {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state != coreRunning {
		return commandFailure("CORE_NOT_RUNNING", "core is not running")
	}
	var data []byte
	var err error
	if rollback {
		configPath, data = runtime.previousConfigPath, runtime.previousConfigData
		if configPath == "" || len(data) == 0 {
			return commandFailure("INVALID_STATE", "previous configuration is unavailable")
		}
	} else {
		data, err = os.ReadFile(configPath)
		if err != nil {
			return commandFailure("CONFIG_INVALID", sanitizeCoreError(err))
		}
	}
	C.SetHomeDir(runtime.workDir)
	C.SetConfig(configPath)
	cfg, order, err := parseRuntimeConfigWithSettings(data, runtime.proxyEnabled, runtime.general, runtime.systemDNS)
	if err != nil {
		C.SetConfig(runtime.configPath)
		return commandFailure("CONFIG_INVALID", sanitizeCoreError(err))
	}
	configureReloadTun(cfg, runtime.proxyEnabled)
	// 同时保留模式与节点选择，避免配置回滚后丢失用户的运行时选择。
	previous := runtime.proxySnapshot()
	if err = applyRuntimeConfig(cfg); err != nil {
		oldConfig, restoreErr := runtime.parseActiveConfig(runtime.proxyEnabled)
		if restoreErr == nil {
			// Use the original TUN settings even if the failed apply changed the listener state.
			oldConfig.General.Tun = cfg.General.Tun
			restoreErr = applyRuntimeConfig(oldConfig)
		}
		if restoreErr == nil {
			restoreErr = restoreProxySnapshot(previous)
		}
		if restoreErr != nil {
			failure := fmt.Errorf("configuration apply failed: %v; rollback failed: %v", err, restoreErr)
			runtime.setFailure(coreInternalError, failure)
			emitCoreEvent(coreEventUnexpectedExit, coreFailed, coreInternalError, runtime.lastError)
			return commandFailure("ROLLBACK_FAILED", runtime.lastError)
		}
		return commandFailure("APPLY_FAILED", sanitizeCoreError(err))
	}
	runtime.previousConfigPath, runtime.previousConfigData = runtime.configPath, runtime.configData
	runtime.configPath, runtime.configData = configPath, data
	runtime.proxyGroupOrder = order
	runtime.scheduleGeoUpdates()
	runtime.lastError = ""
	return commandSuccess(runtime.proxySnapshot())
}

// configureReloadTun 复用正在工作的 TUN 参数，避免热重载替换平台提供的 FD。
func configureReloadTun(cfg *config.Config, proxyEnabled bool) {
	configureHarmonyCore(cfg)
	if proxyEnabled {
		cfg.General.Tun = listener.GetTunConf()
	}
}

func applyRuntimeConfig(cfg *config.Config) (err error) {
	defer func() {
		if recovered := recover(); recovered != nil {
			err = fmt.Errorf("mihomo apply panic: %v", recovered)
		}
	}()
	executor.ApplyConfig(cfg, true)
	if err := applyHarmonyListeners(cfg); err != nil {
		return err
	}
	// The pinned FlClash branch leaves TUN lifecycle management to its host.
	listener.ReCreateTun(cfg.General.Tun, tunnel.Tunnel)
	if listener.GetTunConf().Enable != cfg.General.Tun.Enable {
		return errors.New("TUN state changed during configuration apply")
	}
	return nil
}

// enableProxy 在接入 TUN 前安装 protect 客户端，使新建出站 socket 绕过 VPN。
func (runtime *coreRuntime) enableProxy(options coreProxyOptions) (code coreErrorCode) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state != coreRunning {
		return runtime.reject(coreInvalidState, errors.New("core is not running"))
	}
	if runtime.proxyEnabled {
		return coreOK
	}
	if options.tunFD < 0 || options.mtu <= 0 {
		return runtime.reject(coreInvalidArgument, errors.New("proxy options are invalid"))
	}
	protect, err := newProtectClient(options.protectSocketPath, options.generation)
	if err != nil {
		return runtime.reject(coreInvalidArgument, err)
	}
	defer func() {
		if recovered := recover(); recovered != nil {
			activeSocketProtect.Store(nil)
			protect.close()
			runtime.proxyEnabled = false
			code = runtime.setFailure(coreStartFailed, fmt.Errorf("enable proxy panic: %v", recovered))
		}
	}()
	cfg, err := runtime.parseActiveConfig(true)
	if err != nil {
		protect.close()
		return runtime.reject(coreConfigInvalid, err)
	}
	configureHarmonyTun(cfg, options.tunFD, options.mtu)
	activeSocketProtect.Store(protect)
	if err = applyConfigAndVerifyTun(cfg); err != nil {
		activeSocketProtect.Store(nil)
		protect.close()
		if rollbackErr := runtime.applyCoreOnlyConfig(); rollbackErr != nil {
			return runtime.setFailure(coreStartFailed,
				fmt.Errorf("enable proxy failed: %v; rollback failed: %v", err, rollbackErr))
		}
		return runtime.reject(coreStartFailed, err)
	}
	runtime.protect = protect
	runtime.proxyEnabled = true
	runtime.lastError = ""
	return coreOK
}

// disableProxy 撤下 TUN 和 protect 通道，保留 Core 供预览、测速和配置操作使用。
func (runtime *coreRuntime) disableProxy() (code coreErrorCode) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state != coreRunning {
		return runtime.reject(coreInvalidState, errors.New("core is not running"))
	}
	if !runtime.proxyEnabled {
		return coreOK
	}
	previousProtect := runtime.protect
	defer func() {
		if recovered := recover(); recovered != nil {
			code = runtime.setFailure(coreStopFailed, fmt.Errorf("disable proxy panic: %v", recovered))
		}
	}()
	if err := runtime.applyCoreOnlyConfig(); err != nil {
		return runtime.reject(coreStopFailed, err)
	}
	activeSocketProtect.Store(nil)
	runtime.protect = nil
	runtime.proxyEnabled = false
	if previousProtect != nil {
		previousProtect.close()
	}
	runtime.lastError = ""
	return coreOK
}

func (runtime *coreRuntime) isProxyEnabled() bool {
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	return runtime.proxyEnabled
}

func (runtime *coreRuntime) parseActiveConfig(autoHealthChecks bool) (*config.Config, error) {
	if runtime.configPath == "" || runtime.workDir == "" {
		return nil, errors.New("active core configuration is unavailable")
	}
	C.SetHomeDir(runtime.workDir)
	C.SetConfig(runtime.configPath)
	cfg, _, err := parseRuntimeConfigWithSettings(runtime.configData, autoHealthChecks, runtime.general, runtime.systemDNS)
	return cfg, err
}

func (runtime *coreRuntime) applyCoreOnlyConfig() error {
	cfg, err := runtime.parseActiveConfig(false)
	if err != nil {
		return err
	}
	configureHarmonyCore(cfg)
	activeSocketProtect.Store(nil)
	return applyRuntimeConfig(cfg)
}

// applyConfigAndVerifyTun 捕获本次应用期间的 TUN 错误，为失败结果补充底层原因。
func applyConfigAndVerifyTun(cfg *config.Config) error {
	logSubscription := coreLog.Subscribe()
	tunErrorChannel := make(chan string, 1)
	go func() {
		tunError := ""
		for event := range logSubscription {
			if strings.HasPrefix(event.Payload, "Start TUN listening error:") {
				tunError = event.Payload
			}
		}
		tunErrorChannel <- tunError
	}()

	err := applyRuntimeConfig(cfg)
	coreLog.UnSubscribe(logSubscription)
	tunError := <-tunErrorChannel
	if err != nil && tunError != "" {
		return errors.New(tunError)
	}
	return err
}

const (
	defaultGeoBaseURL = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/"
	mirrorGeoBaseURL  = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/"
)

func parseConfigWithPath(configPath string) (*config.Config, error) {
	cfg, _, err := parseRuntimeConfigWithPath(configPath)
	return cfg, err
}

func parseRuntimeConfigWithPath(configPath string) (*config.Config, []string, error) {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, nil, err
	}
	return parseRuntimeConfigData(data, true)
}

// parseRuntimeConfigData 在解析前适配平台资源与健康检查，并保留 YAML 中的策略组顺序。
func parseRuntimeConfigData(data []byte, autoHealthChecks bool) (*config.Config, []string, error) {
	settings, err := readGeneralSettings(C.Path.HomeDir())
	if err != nil {
		return nil, nil, err
	}
	return parseRuntimeConfigWithSettings(data, autoHealthChecks, settings, nil)
}

func parseRuntimeConfigWithSettings(data []byte, autoHealthChecks bool, settings generalSettings,
	systemDNS []string) (*config.Config, []string, error) {
	raw, err := config.UnmarshalRawConfig(data)
	if err != nil {
		return nil, nil, err
	}
	proxyGroupOrder := rawProxyGroupOrder(raw)
	applyGeneralOverrides(raw, settings, systemDNS)
	applyHarmonyGeoMirrors(raw)
	if err := applySavedGeoSettings(raw, C.Path.HomeDir()); err != nil {
		return nil, nil, err
	}
	if !autoHealthChecks {
		disableAutomaticHealthChecks(raw)
	}
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		return nil, nil, err
	}
	if !autoHealthChecks {
		pauseCompatibleHealthChecks(cfg)
	}
	return cfg, proxyGroupOrder, nil
}

func rawProxyGroupOrder(raw *config.RawConfig) []string {
	order := make([]string, 0, len(raw.ProxyGroup))
	seen := make(map[string]bool)
	for _, mapping := range raw.ProxyGroup {
		name, ok := mapping["name"].(string)
		name = strings.TrimSpace(name)
		if ok && name != "" && !seen[name] {
			seen[name] = true
			order = append(order, name)
		}
	}
	return order
}

// configHomeDir 让 profiles 下的配置共用 Core 工作目录，复用下载的规则与地理数据。
func configHomeDir(configPath string) string {
	configDir := filepath.Dir(filepath.Clean(configPath))
	if filepath.Base(configDir) == "profiles" {
		return filepath.Join(filepath.Dir(configDir), "core", "work")
	}
	return configDir
}

func prepareConfigHome(configPath string) (string, error) {
	homeDir := configHomeDir(configPath)
	if err := os.MkdirAll(homeDir, 0700); err != nil {
		return "", err
	}
	return homeDir, nil
}

// applyHarmonyGeoMirrors 仅替换上游默认资源地址，保留配置显式指定的下载源。
func applyHarmonyGeoMirrors(raw *config.RawConfig) {
	if raw.GeoXUrl.Mmdb == defaultGeoBaseURL+"geoip.metadb" {
		raw.GeoXUrl.Mmdb = mirrorGeoBaseURL + "geoip.metadb"
	}
	if raw.GeoXUrl.GeoIp == defaultGeoBaseURL+"geoip.dat" {
		raw.GeoXUrl.GeoIp = mirrorGeoBaseURL + "geoip.dat"
	}
	if raw.GeoXUrl.GeoSite == defaultGeoBaseURL+"geosite.dat" {
		raw.GeoXUrl.GeoSite = mirrorGeoBaseURL + "geosite.dat"
	}
	if raw.GeoXUrl.ASN == defaultGeoBaseURL+"GeoLite2-ASN.mmdb" {
		raw.GeoXUrl.ASN = mirrorGeoBaseURL + "GeoLite2-ASN.mmdb"
	}
}

// configureHarmonyTun 使用系统创建的 TUN；地址、路由和 VPN 授权由 HarmonyOS 宿主管理。
func configureHarmonyTun(cfg *config.Config, tunFD int, mtu int) {
	cfg.General.Tun.Enable = true
	cfg.General.Tun.Device = "nlash0"
	cfg.General.Tun.FileDescriptor = tunFD
	cfg.General.Tun.MTU = uint32(mtu)
	cfg.General.Tun.Stack = C.TunSystem
	cfg.General.Tun.Inet4Address = []netip.Prefix{netip.MustParsePrefix("172.19.0.1/30")}
	cfg.General.Tun.Inet6Address = nil
	if cfg.General.IPv6 {
		cfg.General.Tun.Inet6Address = []netip.Prefix{netip.MustParsePrefix("fdfe:dcba:9876::1/126")}
	}
	cfg.General.Tun.DNSHijack = []string{"any:53"}
	cfg.General.Tun.AutoRoute = false
	cfg.General.Tun.AutoDetectInterface = false
	cfg.General.Tun.AutoRedirect = false
	cfg.General.Tun.StrictRoute = false
}

// configureHarmonyCore 禁用 Mihomo 自建 TUN 和路由管理，支持 Core 独立运行。
func configureHarmonyCore(cfg *config.Config) {
	cfg.General.Tun.Enable = false
	cfg.General.Tun.FileDescriptor = -1
	cfg.General.Tun.AutoRoute = false
	cfg.General.Tun.AutoDetectInterface = false
	cfg.General.Tun.AutoRedirect = false
	cfg.General.Tun.StrictRoute = false
}

// protectSocket 必须收到宿主确认后才允许拨号继续，防止出站流量重新进入 TUN。
func protectSocket(protect *protectClient, connection syscall.RawConn) error {
	var fd int = -1
	if err := connection.Control(func(value uintptr) {
		fd = int(value)
	}); err != nil {
		return fmt.Errorf("read outbound socket: %w", err)
	}
	if protect == nil {
		return errors.New("protect channel is unavailable")
	}
	if err := protect.protect(fd); err != nil {
		emitCoreEvent(coreEventProtectFailure, coreRunning, coreProtectFailed, "outbound socket protect failed")
		return fmt.Errorf("protect outbound socket: %w", err)
	}
	return nil
}

// stop 先撤销拨号钩子的客户端，再关闭 Core 与通道，清空本轮配置和回滚快照。
func (runtime *coreRuntime) stop() (code coreErrorCode) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state == coreStopped {
		return coreOK
	}
	if runtime.state == coreStopping {
		return coreInvalidState
	}
	runtime.state = coreStopping
	runtime.scheduleGeoUpdates()
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "stopping core")
	defer func() {
		if recovered := recover(); recovered != nil {
			code = runtime.setFailure(coreStopFailed, fmt.Errorf("mihomo stop panic: %v", recovered))
		}
	}()
	activeSocketProtect.Store(nil)
	executor.Shutdown()
	if err := applyController("", ""); err != nil {
		return runtime.setFailure(coreStopFailed, err)
	}
	protect := runtime.protect
	runtime.protect = nil
	if protect != nil {
		protect.close()
	}
	runtime.proxyEnabled = false
	runtime.configPath = ""
	runtime.configData = nil
	runtime.previousConfigPath = ""
	runtime.previousConfigData = nil
	runtime.proxyGroupOrder = nil
	runtime.lastError = ""
	runtime.state = coreStopped
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "core is stopped")
	return coreOK
}

func sanitizeCoreError(err error) string {
	if err == nil {
		return ""
	}
	return sanitizeCoreErrorText(err.Error())
}

// sanitizeCoreErrorText 只折叠换行并限制长度，不承担 URL、路径或凭据的内容脱敏。
func sanitizeCoreErrorText(value string) string {
	message := strings.ReplaceAll(value, "\r", " ")
	message = strings.ReplaceAll(message, "\n", " ")
	if len(message) > 240 {
		message = message[:240]
	}
	return message
}
