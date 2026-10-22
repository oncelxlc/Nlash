package main

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func writeTestGeneralSettings(t *testing.T, dir string) {
	t.Helper()
	settings := defaultGeneralSettings()
	settings.MixedPort = 0
	data, err := json.Marshal(settings)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, generalSettingsFile), data, 0600); err != nil {
		t.Fatal(err)
	}
}

type selectionTestTracker struct {
	C.Connection
	closed bool
}

func (tracker *selectionTestTracker) ID() string                   { return "general-selection-test" }
func (tracker *selectionTestTracker) Info() *statistic.TrackerInfo { return &statistic.TrackerInfo{} }
func (tracker *selectionTestTracker) Close() error {
	tracker.closed = true
	statistic.DefaultManager.Leave(tracker)
	return nil
}

func TestGeneralDefaultsMigrationAndValidation(t *testing.T) {
	dir := t.TempDir()
	for _, data := range []string{"", "{}", `{"mixedPort":1080,"hosts":null}`} {
		if data != "" {
			if err := os.WriteFile(filepath.Join(dir, generalSettingsFile), []byte(data), 0600); err != nil {
				t.Fatal(err)
			}
		}
		settings, err := readGeneralSettings(dir)
		if err != nil || !settings.UnifiedDelay || !settings.TCPConcurrent || !settings.GeoMemoryMode ||
			!settings.AutoCloseConnections || settings.IPv6 || settings.Hosts == nil {
			t.Fatalf("default migration failed: %+v, %v", settings, err)
		}
	}
	for _, payload := range []string{
		`{"mixedPort":-1}`, `{"mixedPort":65536}`, `{"externalController":true,"controllerSecret":""}`,
		`{"authentication":true}`, `{"username":"user:name"}`, `{"password":"a\nb"}`,
		`{"hosts":[{"host":"test.invalid","value":"bad:ip"}]}`,
		`{"hosts":[{"host":"bad..invalid","value":"1.1.1.1"}]}`,
		`{"hosts":[{"host":"test.invalid","value":"1.1.1.1"},{"host":"TEST.invalid","value":"2.2.2.2"}]}`,
	} {
		settings := defaultGeneralSettings()
		if err := json.Unmarshal([]byte(payload), &settings); err != nil {
			t.Fatal(err)
		}
		if validateGeneralSettings(settings) == nil {
			t.Fatalf("invalid settings accepted: %s", payload)
		}
	}
}

func TestGeneralOverridesPreserveProfileAndEnforceAuthentication(t *testing.T) {
	raw, err := config.UnmarshalRawConfig([]byte("hosts: {profile.invalid: 1.1.1.1, LOCAL.invalid: 2.2.2.2}\nskip-auth-prefixes: [127.0.0.0/8]\n" +
		"dns: {enable: true, nameserver: [8.8.8.8]}\nrules: [MATCH,DIRECT]\n"))
	if err != nil {
		t.Fatal(err)
	}
	settings := defaultGeneralSettings()
	settings.Authentication, settings.Username, settings.Password = true, "user", "pass:word"
	settings.ExternalController, settings.ControllerSecret = true, "secret"
	settings.IPv6, settings.FindProcess, settings.AppendSystemDNS = true, true, true
	settings.Hosts = []hostOverride{{Host: "local.invalid", Value: "192.0.2.1, 2001:db8::1"}}
	applyGeneralOverrides(raw, settings, []string{"8.8.8.8", "192.0.2.53"})
	if !reflect.DeepEqual(raw.Authentication, []string{"user:pass:word"}) || len(raw.SkipAuthPrefixes) != 0 ||
		raw.ExternalController != "127.0.0.1:9090" || raw.FindProcessMode != process.FindProcessAlways ||
		!raw.IPv6 || !raw.DNS.IPv6 || raw.GeodataLoader != "memconservative" {
		t.Fatal("core settings or authentication not applied")
	}
	if len(raw.Hosts) != 2 || raw.Hosts["profile.invalid"] != "1.1.1.1" ||
		!reflect.DeepEqual(raw.DNS.NameServer, []string{"8.8.8.8", "192.0.2.53"}) {
		t.Fatal("profile hosts or DNS were discarded")
	}
	settings = defaultGeneralSettings()
	settings.GeoMemoryMode = false
	applyGeneralOverrides(raw, settings, nil)
	if raw.ExternalController != "" || len(raw.Authentication) != 0 || raw.FindProcessMode != process.FindProcessOff ||
		raw.IPv6 || raw.GeodataLoader != "standard" {
		t.Fatal("disabled options were retained")
	}
}

func TestGeneralSettingsApplyPersistAndRollback(t *testing.T) {
	dir := t.TempDir()
	writeTestGeneralSettings(t, dir)
	path := filepath.Join(dir, "profile.yaml")
	original := []byte("dns: {enable: false}\nproxy-groups:\n  - {name: Route, type: select, proxies: [DIRECT, REJECT]}\nrules: ['MATCH,DIRECT']\n")
	if err := os.WriteFile(path, original, 0600); err != nil {
		t.Fatal(err)
	}
	runtime := &coreRuntime{state: coreStopped}
	t.Cleanup(func() { closeDelayTestRuntime(runtime) })
	if code := runtime.start(coreStartOptions{configPath: path, workDir: dir}); code != coreOK {
		t.Fatal(runtime.lastError)
	}
	if err := selectProxy("Route", "REJECT", false); err != nil {
		t.Fatal(err)
	}
	result := runtime.saveGeneralSettings(json.RawMessage(`{"unifiedDelay":false,"authentication":true,"autoCloseConnections":false,"onlyProxyTraffic":true}`))
	if !result.OK || adapter.UnifiedDelay.Load() || runtime.general.Username == "" || len(runtime.general.Password) != 32 {
		t.Fatalf("settings did not apply: %+v", result)
	}
	saved, err := readGeneralSettings(dir)
	if err != nil || !reflect.DeepEqual(saved, runtime.general) || !runtime.dashboardSnapshot().OnlyProxyTraffic {
		t.Fatal("saved settings or traffic scope mismatch")
	}
	if string(runtime.configData) != string(original) || runtime.proxySnapshot().Groups[0].Selected != "REJECT" {
		t.Fatal("settings replaced profile content or selection")
	}
	// Occupy a real port: saving must reject it and restore the prior running configuration.
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer busy.Close()
	port := busy.Addr().(*net.TCPAddr).Port
	payload, _ := json.Marshal(map[string]any{"mixedPort": port})
	result = runtime.saveGeneralSettings(payload)
	if result.OK || runtime.state != coreRunning || listener.GetPorts().MixedPort != 0 || adapter.UnifiedDelay.Load() {
		t.Fatalf("failed apply did not roll back: %+v", result)
	}
	after, err := readGeneralSettings(dir)
	if err != nil || !reflect.DeepEqual(saved, after) {
		t.Fatal("failed save replaced persisted settings")
	}
	if result = runtime.saveGeneralSettings(json.RawMessage(`{"password":""}`)); result.OK {
		t.Fatal("blank active password was accepted")
	}
	tracker := &selectionTestTracker{}
	statistic.DefaultManager.Join(tracker)
	t.Cleanup(func() { statistic.DefaultManager.Leave(tracker) })
	if response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"selectProxy","payload":{"group":"Route","proxy":"DIRECT"}}`)); !response.OK || tracker.closed {
		t.Fatal("disabled automatic close terminated the connection")
	}
	runtime.general.AutoCloseConnections = true
	if response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"selectProxy","payload":{"group":"Route","proxy":"DIRECT"}}`)); !response.OK || tracker.closed {
		t.Fatal("reselecting the same node terminated the connection")
	}
	if response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"selectProxy","payload":{"group":"Route","proxy":"REJECT"}}`)); !response.OK || !tracker.closed {
		t.Fatal("enabled automatic close did not terminate the connection")
	}
}

func TestOnlyProxyTrafficExcludesDirectCounters(t *testing.T) {
	statistic.DefaultManager.ResetStatistic()
	t.Cleanup(func() { statistic.DefaultManager.ResetStatistic() })
	statistic.DefaultManager.PushUploaded(true, 500)
	statistic.DefaultManager.PushUploaded(false, 40)
	statistic.DefaultManager.PushDownloaded(true, 1000)
	statistic.DefaultManager.PushDownloaded(false, 80)
	runtime := &coreRuntime{proxyEnabled: true}
	all := runtime.dashboardSnapshot()
	runtime.general.OnlyProxyTraffic = true
	proxy := runtime.dashboardSnapshot()
	if all.UploadTotal != 540 || all.DownloadTotal != 1080 || proxy.UploadTotal != 40 || proxy.DownloadTotal != 80 {
		t.Fatal("proxy-only traffic included direct traffic")
	}
}

func TestMixedListenerRequiresAuthenticationEvenOnLoopback(t *testing.T) {
	dir := t.TempDir()
	writeTestGeneralSettings(t, dir)
	path := filepath.Join(dir, "profile.yaml")
	if err := os.WriteFile(path, []byte("dns: {enable: false}\nskip-auth-prefixes: [127.0.0.0/8]\nrules: ['MATCH,DIRECT']\n"), 0600); err != nil {
		t.Fatal(err)
	}
	runtime := &coreRuntime{state: coreStopped}
	t.Cleanup(func() { closeDelayTestRuntime(runtime) })
	if runtime.start(coreStartOptions{configPath: path, workDir: dir}) != coreOK {
		t.Fatal(runtime.lastError)
	}
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := probe.Addr().(*net.TCPAddr).Port
	probe.Close()
	payload, _ := json.Marshal(map[string]any{"mixedPort": port, "authentication": true})
	if result := runtime.saveGeneralSettings(payload); !result.OK {
		t.Fatal(result)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) }))
	defer server.Close()
	proxyURL, _ := url.Parse("http://" + net.JoinHostPort("127.0.0.1", fmt.Sprint(port)))
	for _, authenticated := range []bool{false, true} {
		if authenticated {
			proxyURL.User = url.UserPassword(runtime.general.Username, runtime.general.Password)
		}
		client := &http.Client{Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL)}, Timeout: 3 * time.Second}
		response, err := client.Get(server.URL)
		client.CloseIdleConnections()
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if (!authenticated && response.StatusCode != http.StatusProxyAuthRequired) || (authenticated && response.StatusCode != http.StatusNoContent) {
			t.Fatalf("unexpected mixed proxy authentication status: %d", response.StatusCode)
		}
	}
}

func TestGeneralSettingsCanRepairAStartupPortConflict(t *testing.T) {
	dir := t.TempDir()
	busy, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer busy.Close()
	settings := defaultGeneralSettings()
	settings.MixedPort = busy.Addr().(*net.TCPAddr).Port
	data, _ := json.Marshal(settings)
	if err := os.WriteFile(filepath.Join(dir, generalSettingsFile), data, 0600); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(dir, "profile.yaml")
	if err := os.WriteFile(path, []byte("dns: {enable: false}\nrules: ['MATCH,DIRECT']\n"), 0600); err != nil {
		t.Fatal(err)
	}
	runtime := &coreRuntime{state: coreStopped}
	t.Cleanup(func() { closeDelayTestRuntime(runtime) })
	if code := runtime.start(coreStartOptions{configPath: path, workDir: dir}); code != coreStartFailed {
		t.Fatal("occupied port unexpectedly started")
	}
	if response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"generalSettings"}`)); !response.OK {
		t.Fatal("failed core prevented reading settings")
	}
	if result := runtime.saveGeneralSettings(json.RawMessage(`{"mixedPort":0}`)); !result.OK {
		t.Fatal("failed core prevented repairing settings")
	}
	if code := runtime.start(coreStartOptions{configPath: path, workDir: dir}); code != coreOK {
		t.Fatal(runtime.lastError)
	}
}

func TestControllerRequiresSecretAndCloses(t *testing.T) {
	probe, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	address := probe.Addr().String()
	probe.Close()
	if err = applyController(address, "test-secret"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = applyController("", "") })
	client := &http.Client{Transport: &http.Transport{Proxy: nil}}
	defer client.CloseIdleConnections()
	for _, secret := range []string{"", "test-secret"} {
		request, _ := http.NewRequest(http.MethodGet, "http://"+address+"/version", nil)
		if secret != "" {
			request.Header.Set("Authorization", "Bearer "+secret)
		}
		response, err := client.Do(request)
		if err != nil {
			t.Fatal(err)
		}
		response.Body.Close()
		if (secret == "" && response.StatusCode != http.StatusUnauthorized) || (secret != "" && response.StatusCode != http.StatusOK) {
			t.Fatalf("unexpected controller authentication status: %d", response.StatusCode)
		}
	}
	if err = applyController("", ""); err != nil {
		t.Fatal(err)
	}
	conn, err := net.Dial("tcp", address)
	if err == nil {
		conn.Close()
		t.Fatal("controller is still listening")
	}
}

func TestGeneralIPv6KeepsPlatformRoutingUnderHostControl(t *testing.T) {
	cfg := &config.Config{General: &config.General{IPv6: true}}
	configureHarmonyTun(cfg, 37, 1400)
	if len(cfg.General.Tun.Inet6Address) != 1 || cfg.General.Tun.Inet6Address[0].String() != "fdfe:dcba:9876::1/126" {
		t.Fatal("missing IPv6 TUN address")
	}
	configureHarmonyCore(cfg)
	if !cfg.General.IPv6 || cfg.General.Tun.Enable || cfg.General.Tun.AutoRoute {
		t.Fatal("core-only configuration discarded IPv6 or gained platform routing")
	}
}

func TestSystemDNSRejectsLoopbackAndDoesNotPersistNetworkData(t *testing.T) {
	runtime := &coreRuntime{state: coreStopped}
	for _, payload := range []string{`["127.0.0.1"]`, `["::1"]`, `["system://"]`, `["0.0.0.0"]`} {
		if response := runtime.updateSystemDNS(json.RawMessage(payload)); response.OK {
			t.Fatalf("invalid system DNS accepted: %s", payload)
		}
	}
	if response := runtime.updateSystemDNS(json.RawMessage(`["192.0.2.53","2001:db8::53"]`)); !response.OK {
		t.Fatal(response)
	}
	data, _ := json.Marshal(runtime.general)
	if strings.Contains(string(data), "192.0.2.53") {
		t.Fatal("network DNS leaked into persistent settings")
	}
	C.SetHomeDir(t.TempDir())
}

func TestPreviewDelayHonorsSavedUnifiedDelay(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) }))
	defer server.Close()
	dir, path := writeDelayLifecycleConfig(t, server.URL)
	settings := defaultGeneralSettings()
	settings.MixedPort, settings.UnifiedDelay = 0, false
	data, _ := json.Marshal(settings)
	if err := os.WriteFile(filepath.Join(dir, generalSettingsFile), data, 0600); err != nil {
		t.Fatal(err)
	}
	previous := adapter.UnifiedDelay.Load()
	t.Cleanup(func() { adapter.UnifiedDelay.Store(previous) })
	runtime := &coreRuntime{state: coreStopped}
	if _, err := runtime.previewGroupDelay(previewGroupDelayPayload{ConfigPath: path, Group: "Route", Proxy: "DIRECT", URL: server.URL, Timeout: 1000}); err != nil {
		t.Fatal(err)
	}
	if adapter.UnifiedDelay.Load() {
		t.Fatal("preview ignored saved unified-delay setting")
	}
}
