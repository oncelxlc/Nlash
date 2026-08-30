package main

import (
	"errors"
	"testing"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
)

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
