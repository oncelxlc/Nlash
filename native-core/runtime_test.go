package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/metacubex/mihomo/component/profile/cachefile"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel"
)

func TestConfigurationHotApplyPreservesRuntimeAndAcceptedData(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "active.yaml")
	bootstrap := []byte("port: 0\nsocks-port: 0\nmixed-port: 0\nexternal-controller: ''\n" +
		"dns:\n  enable: false\ntun:\n  enable: false\nrules:\n  - MATCH,REJECT\n")
	if err := os.WriteFile(path, bootstrap, 0600); err != nil {
		t.Fatal(err)
	}
	runtime := &coreRuntime{state: coreStopped}
	if code := runtime.start(coreStartOptions{configPath: path, workDir: dir}); code != coreOK {
		t.Fatalf("bootstrap failed: %v %s", code, runtime.lastError)
	}
	t.Cleanup(func() {
		runtime.stop()
		if cachefile.Cache().DB != nil {
			if err := cachefile.Cache().Close(); err != nil {
				t.Error(err)
			}
		}
	})
	if runtime.getState() != coreRunning || runtime.isProxyEnabled() || listener.GetTunConf().Enable {
		t.Fatal("bootstrap must run without enabling proxy or TUN")
	}
	starts, stops := 0, 0
	setCoreEventHandler(func(kind coreEventType, state coreRuntimeState, _ coreErrorCode, _ string) {
		if kind == coreEventLifecycle && state == coreStarting {
			starts++
		}
		if kind == coreEventLifecycle && state == coreStopping {
			stops++
		}
	})
	t.Cleanup(func() { setCoreEventHandler(nil) })
	updated := append(append([]byte{}, bootstrap...), []byte("proxy-groups:\n  - name: Route\n    type: select\n    proxies: [DIRECT, REJECT]\n")...)
	if err := os.WriteFile(path, updated, 0600); err != nil {
		t.Fatal(err)
	}
	command, err := json.Marshal(map[string]any{"type": "applyConfig", "payload": map[string]any{"configPath": path}})
	if err != nil {
		t.Fatal(err)
	}
	response := decodeTestCommandResponse(t, runtime.executeCommand(string(command)))
	if !response.OK {
		t.Fatalf("hot apply failed: %+v", response)
	}
	if tunnel.Proxies()["Route"] == nil {
		t.Fatal("updated group is missing")
	}
	if response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"selectProxy","payload":{"group":"Route","proxy":"REJECT"}}`)); !response.OK {
		t.Fatalf("selection failed: %+v", response)
	}
	if response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"setMode","payload":{"mode":"direct"}}`)); !response.OK {
		t.Fatalf("mode change failed: %+v", response)
	}
	if err := os.WriteFile(path, []byte("proxy-groups: ["), 0600); err != nil {
		t.Fatal(err)
	}
	response = decodeTestCommandResponse(t, runtime.executeCommand(string(command)))
	if response.OK || response.Code != "CONFIG_INVALID" {
		t.Fatalf("invalid config accepted: %+v", response)
	}
	if runtime.getState() != coreRunning || string(runtime.configData) != string(updated) {
		t.Fatal("invalid overwrite replaced the accepted configuration")
	}
	if _, err := runtime.parseActiveConfig(); err != nil {
		t.Fatalf("accepted config depends on overwritten file: %v", err)
	}
	if response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"rollbackConfig"}`)); !response.OK {
		t.Fatalf("rollback failed: %+v", response)
	}
	if string(runtime.configData) != string(bootstrap) || tunnel.Proxies()["Route"] != nil {
		t.Fatal("rollback did not restore the previous accepted bytes")
	}
	if code := runtime.disableProxy(); code != coreOK {
		t.Fatalf("idempotent proxy disable failed: %v", code)
	}
	if starts != 0 || stops != 0 {
		t.Fatalf("hot operations restarted core: starts=%d stops=%d", starts, stops)
	}
}

func TestReloadKeepsPlatformTunParameters(t *testing.T) {
	previous := listener.LastTunConf
	t.Cleanup(func() { listener.LastTunConf = previous })
	active := &config.Config{General: &config.General{}}
	configureHarmonyTun(active, 37, 1420)
	listener.LastTunConf = active.General.Tun
	replacement := &config.Config{General: &config.General{}}
	configureReloadTun(replacement, true)
	if !replacement.General.Tun.Equal(active.General.Tun) {
		t.Fatal("reload changed platform TUN settings")
	}
	configureReloadTun(replacement, false)
	if replacement.General.Tun.Enable || replacement.General.Tun.FileDescriptor != -1 {
		t.Fatal("disabled proxy gained a TUN")
	}
}

func TestConfigureHarmonyTunOverridesUnsafeRouting(t *testing.T) {
	cfg := &config.Config{General: &config.General{}}
	cfg.General.Tun.AutoRoute = true
	cfg.General.Tun.AutoDetectInterface = true
	cfg.General.Tun.AutoRedirect = true
	cfg.General.Tun.StrictRoute = true

	configureHarmonyTun(cfg, 37, 1400)

	if !cfg.General.Tun.Enable || cfg.General.Tun.FileDescriptor != 37 || cfg.General.Tun.MTU != 1400 {
		t.Fatalf("unexpected external TUN settings: %+v", cfg.General.Tun)
	}
	if cfg.General.Tun.Inet4Address[0].String() != "172.19.0.1/30" || len(cfg.General.Tun.Inet6Address) != 0 ||
		len(cfg.General.Tun.DNSHijack) != 1 || cfg.General.Tun.DNSHijack[0] != "any:53" {
		t.Fatalf("unexpected IPv4 TUN settings: %+v", cfg.General.Tun)
	}
	if cfg.General.Tun.Stack != C.TunSystem {
		t.Fatalf("unexpected TUN stack: %v", cfg.General.Tun.Stack)
	}
	if cfg.General.Tun.AutoRoute || cfg.General.Tun.AutoDetectInterface ||
		cfg.General.Tun.AutoRedirect || cfg.General.Tun.StrictRoute {
		t.Fatal("platform routing options must be disabled")
	}
}

func TestConfigureHarmonyCoreDisablesTunAndRouting(t *testing.T) {
	cfg := &config.Config{General: &config.General{}}
	cfg.General.Tun.Enable = true
	cfg.General.Tun.FileDescriptor = 37
	cfg.General.Tun.AutoRoute = true
	cfg.General.Tun.AutoDetectInterface = true
	cfg.General.Tun.AutoRedirect = true
	cfg.General.Tun.StrictRoute = true
	cfg.General.IPv6 = true

	configureHarmonyCore(cfg)

	if cfg.General.Tun.Enable || cfg.General.Tun.FileDescriptor != -1 {
		t.Fatalf("core-only runtime retained TUN settings: %+v", cfg.General.Tun)
	}
	if cfg.General.Tun.AutoRoute || cfg.General.Tun.AutoDetectInterface ||
		cfg.General.Tun.AutoRedirect || cfg.General.Tun.StrictRoute || cfg.General.IPv6 {
		t.Fatal("core-only runtime retained platform routing")
	}
}

func TestProxyLifecycleValidatesStateAndIsIdempotent(t *testing.T) {
	stopped := &coreRuntime{state: coreStopped}
	if code := stopped.enableProxy(coreProxyOptions{}); code != coreInvalidState {
		t.Fatalf("unexpected stopped enable result: %v", code)
	}
	if stopped.isProxyEnabled() {
		t.Fatal("stopped runtime must not report proxy enabled")
	}

	running := &coreRuntime{state: coreRunning}
	if code := running.enableProxy(coreProxyOptions{tunFD: -1, mtu: 1400}); code != coreInvalidArgument {
		t.Fatalf("unexpected invalid proxy options result: %v", code)
	}
	if code := running.disableProxy(); code != coreOK {
		t.Fatalf("disabling an already disabled proxy must be idempotent: %v", code)
	}
}

func TestInvalidOperationDoesNotReplaceRunningState(t *testing.T) {
	runtime := &coreRuntime{state: coreRunning}
	if code := runtime.validate("ignored.yaml"); code != coreInvalidState {
		t.Fatalf("unexpected error code: %v", code)
	}
	if runtime.getState() != coreRunning {
		t.Fatalf("running state was replaced: %v", runtime.getState())
	}
}

func TestSanitizeCoreErrorRemovesLinesAndCapsLength(t *testing.T) {
	message := sanitizeCoreError(errors.New("first\r\nsecond"))
	if message != "first  second" {
		t.Fatalf("unexpected sanitized message: %q", message)
	}
	long := sanitizeCoreError(errors.New(string(make([]byte, 300))))
	if len(long) != 240 {
		t.Fatalf("unexpected maximum error length: %d", len(long))
	}
}
