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
	configPath        string
	workDir           string
	tunFD             int
	mtu               int
	protectSocketPath string
	generation        string
}

type coreRuntime struct {
	mu        sync.Mutex
	state     coreRuntimeState
	lastError string
	protect   *protectClient
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
	if options.configPath == "" || options.workDir == "" || options.tunFD < 0 || options.mtu <= 0 {
		return runtime.setFailure(coreInvalidArgument, errors.New("core start options are invalid"))
	}
	protect, err := newProtectClient(options.protectSocketPath, options.generation)
	if err != nil {
		return runtime.setFailure(coreInvalidArgument, err)
	}
	if err = os.MkdirAll(options.workDir, 0700); err != nil {
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
	configureHarmonyTun(cfg, options.tunFD, options.mtu)
	runtime.protect = protect
	dialer.DefaultSocketHook = runtime.protectSocket
	executor.ApplyConfig(cfg, true)
	runtime.state = coreRunning
	emitCoreEvent(coreEventLifecycle, runtime.state, coreOK, "core is running")
	return coreOK
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
	cfg.General.Tun.Stack = C.TunGvisor
	cfg.General.Tun.Inet4Address = []netip.Prefix{netip.MustParsePrefix("172.19.0.1/30")}
	cfg.General.Tun.Inet6Address = nil
	cfg.General.Tun.DNSHijack = []string{"any:53"}
	cfg.General.Tun.AutoRoute = false
	cfg.General.Tun.AutoDetectInterface = false
	cfg.General.Tun.AutoRedirect = false
	cfg.General.Tun.StrictRoute = false
	cfg.General.IPv6 = false
}

func (runtime *coreRuntime) protectSocket(_ string, _ string, connection syscall.RawConn) error {
	var fd int = -1
	if err := connection.Control(func(value uintptr) {
		fd = int(value)
	}); err != nil {
		return fmt.Errorf("read outbound socket: %w", err)
	}
	if runtime.protect == nil {
		return errors.New("protect channel is unavailable")
	}
	if err := runtime.protect.protect(fd); err != nil {
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
	runtime.protect = nil
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
