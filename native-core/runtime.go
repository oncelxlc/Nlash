package main

import (
	"errors"
	"fmt"
	"net/netip"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"syscall"

	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	coreLog "github.com/metacubex/mihomo/log"
)

type coreRuntimeState int32

const (
	coreStopped coreRuntimeState = iota
	coreValidating
	coreStarting
	coreRunning
	coreStopping
	coreFailed
)

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

type coreProxyOptions struct {
	tunFD             int
	mtu               int
	protectSocketPath string
	generation        string
}

type coreRuntime struct {
	mu           sync.Mutex
	state        coreRuntimeState
	lastError    string
	protect      *protectClient
	configPath   string
	workDir      string
	proxyEnabled bool
}

var runtimeInstance = &coreRuntime{state: coreStopped}

func (runtime *coreRuntime) getState() coreRuntimeState {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.state
}

func (runtime *coreRuntime) getLastError() string {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.lastError
}

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

func (runtime *coreRuntime) start(options coreStartOptions) (code coreErrorCode) {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state != coreStopped && runtime.state != coreFailed {
		return runtime.reject(coreInvalidState, errors.New("core is already active"))
	}
	runtime.state = coreStarting
	runtime.lastError = ""
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "starting core")
	if options.configPath == "" || options.workDir == "" {
		return runtime.setFailure(coreInvalidArgument, errors.New("core start options are invalid"))
	}
	if err := os.MkdirAll(options.workDir, 0700); err != nil {
		return runtime.setFailure(coreStartFailed, err)
	}

	defer func() {
		if recovered := recover(); recovered != nil {
			code = runtime.setFailure(coreInternalError, fmt.Errorf("mihomo start panic: %v", recovered))
		}
	}()
	C.SetHomeDir(options.workDir)
	C.SetConfig(options.configPath)
	cfg, err := parseConfigWithPath(options.configPath)
	if err != nil {
		return runtime.setFailure(coreConfigInvalid, err)
	}
	configureHarmonyCore(cfg)
	if runtime.protect != nil {
		runtime.protect.close()
	}
	runtime.protect = nil
	runtime.proxyEnabled = false
	dialer.DefaultSocketHook = nil
	executor.ApplyConfig(cfg, true)
	runtime.configPath = options.configPath
	runtime.workDir = options.workDir
	runtime.state = coreRunning
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "core is running")
	return coreOK
}

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
			dialer.DefaultSocketHook = nil
			protect.close()
			runtime.proxyEnabled = false
			code = runtime.setFailure(coreStartFailed, fmt.Errorf("enable proxy panic: %v", recovered))
		}
	}()
	cfg, err := runtime.parseActiveConfig()
	if err != nil {
		protect.close()
		return runtime.reject(coreConfigInvalid, err)
	}
	configureHarmonyTun(cfg, options.tunFD, options.mtu)
	dialer.DefaultSocketHook = func(_ string, _ string, connection syscall.RawConn) error {
		return protectSocket(protect, connection)
	}
	if err = applyConfigAndVerifyTun(cfg); err != nil {
		dialer.DefaultSocketHook = nil
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
	dialer.DefaultSocketHook = nil
	runtime.protect = nil
	runtime.proxyEnabled = false
	if previousProtect != nil {
		previousProtect.close()
	}
	runtime.lastError = ""
	return coreOK
}

func (runtime *coreRuntime) isProxyEnabled() bool {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	return runtime.proxyEnabled
}

func (runtime *coreRuntime) parseActiveConfig() (*config.Config, error) {
	if runtime.configPath == "" || runtime.workDir == "" {
		return nil, errors.New("active core configuration is unavailable")
	}
	C.SetHomeDir(runtime.workDir)
	C.SetConfig(runtime.configPath)
	return parseConfigWithPath(runtime.configPath)
}

func (runtime *coreRuntime) applyCoreOnlyConfig() error {
	cfg, err := runtime.parseActiveConfig()
	if err != nil {
		return err
	}
	configureHarmonyCore(cfg)
	dialer.DefaultSocketHook = nil
	executor.ApplyConfig(cfg, true)
	if listener.GetTunConf().Enable {
		return errors.New("TUN listener did not stop")
	}
	return nil
}

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

	executor.ApplyConfig(cfg, true)
	coreLog.UnSubscribe(logSubscription)
	tunError := <-tunErrorChannel
	if !listener.GetTunConf().Enable {
		if tunError == "" {
			tunError = "TUN listener did not start"
		}
		return errors.New(tunError)
	}
	return nil
}

const (
	defaultGeoBaseURL = "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/"
	mirrorGeoBaseURL  = "https://testingcf.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/"
)

func parseConfigWithPath(configPath string) (*config.Config, error) {
	data, err := os.ReadFile(configPath)
	if err != nil {
		return nil, err
	}
	raw, err := config.UnmarshalRawConfig(data)
	if err != nil {
		return nil, err
	}
	applyHarmonyGeoMirrors(raw)
	return config.ParseRawConfig(raw)
}

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

func configureHarmonyTun(cfg *config.Config, tunFD int, mtu int) {
	cfg.General.Tun.Enable = true
	cfg.General.Tun.Device = "nlash0"
	cfg.General.Tun.FileDescriptor = tunFD
	cfg.General.Tun.MTU = uint32(mtu)
	cfg.General.Tun.Stack = C.TunSystem
	cfg.General.Tun.Inet4Address = []netip.Prefix{netip.MustParsePrefix("172.19.0.1/30")}
	cfg.General.Tun.Inet6Address = nil
	cfg.General.Tun.DNSHijack = []string{"any:53"}
	cfg.General.Tun.AutoRoute = false
	cfg.General.Tun.AutoDetectInterface = false
	cfg.General.Tun.AutoRedirect = false
	cfg.General.Tun.StrictRoute = false
	cfg.General.IPv6 = false
}

func configureHarmonyCore(cfg *config.Config) {
	cfg.General.Tun.Enable = false
	cfg.General.Tun.FileDescriptor = -1
	cfg.General.Tun.AutoRoute = false
	cfg.General.Tun.AutoDetectInterface = false
	cfg.General.Tun.AutoRedirect = false
	cfg.General.Tun.StrictRoute = false
	cfg.General.IPv6 = false
}

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
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "stopping core")
	defer func() {
		if recovered := recover(); recovered != nil {
			code = runtime.setFailure(coreStopFailed, fmt.Errorf("mihomo stop panic: %v", recovered))
		}
	}()
	dialer.DefaultSocketHook = nil
	executor.Shutdown()
	protect := runtime.protect
	runtime.protect = nil
	if protect != nil {
		protect.close()
	}
	runtime.proxyEnabled = false
	runtime.configPath = ""
	runtime.workDir = ""
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

func sanitizeCoreErrorText(value string) string {
	message := strings.ReplaceAll(value, "\r", " ")
	message = strings.ReplaceAll(message, "\n", " ")
	if len(message) > 240 {
		message = message[:240]
	}
	return message
}
