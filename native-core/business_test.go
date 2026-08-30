package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
)

func TestExecuteCommandRejectsInvalidInput(t *testing.T) {
	runtime := &coreRuntime{state: coreStopped}
	for _, input := range []string{"", "{", strings.Repeat("x", maxCoreCommandBytes+1)} {
		response := decodeTestCommandResponse(t, runtime.executeCommand(input))
		if response.OK || response.Code != "INVALID_ARGUMENT" || response.Message == "" {
			t.Fatalf("unexpected invalid command response: %+v", response)
		}
	}
}

func TestExecuteCommandRequiresRunningCore(t *testing.T) {
	runtime := &coreRuntime{state: coreStopped}
	response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"dashboardSnapshot"}`))
	if response.OK || response.Code != "CORE_NOT_RUNNING" {
		t.Fatalf("unexpected stopped response: %+v", response)
	}
}

func TestPreviewProxySnapshotAllowedWhileStopped(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "profile.yaml")
	content := `
proxies:
  - name: node-a
    type: ss
    server: 127.0.0.1
    port: 8388
    cipher: aes-128-gcm
    password: test
  - name: node-b
    type: ss
    server: 127.0.0.1
    port: 8389
    cipher: aes-128-gcm
    password: test
proxy-groups:
  - name: First
    type: select
    proxies: [node-a, node-b]
  - name: Second
    type: select
    proxies: [node-b]
rules:
  - MATCH,First
`
	if err := os.WriteFile(path, []byte(content), 0600); err != nil {
		t.Fatal(err)
	}
	runtime := &coreRuntime{state: coreStopped}
	rawCommand, _ := json.Marshal(map[string]any{
		"type":    "previewProxySnapshot",
		"payload": map[string]any{"configPath": path},
	})
	response := decodeTestCommandResponse(t, runtime.executeCommand(string(rawCommand)))
	if !response.OK || response.Code != "OK" {
		t.Fatalf("unexpected preview response: %+v", response)
	}
	data, _ := json.Marshal(response.Data)
	var snapshot proxySnapshot
	if err := json.Unmarshal(data, &snapshot); err != nil {
		t.Fatal(err)
	}
	if snapshot.Source != "config" || snapshot.Mode != "rule" || len(snapshot.Groups) < 2 ||
		snapshot.Groups[0].Name != "First" || snapshot.Groups[1].Name != "Second" ||
		len(snapshot.Groups[0].Nodes) != 2 || snapshot.Groups[0].Nodes[0].Tested {
		t.Fatalf("unexpected preview snapshot: %+v", snapshot)
	}
	for index, group := range snapshot.Groups {
		if group.Name == "GLOBAL" && index < 2 {
			t.Fatalf("generated GLOBAL group must follow configured groups: %+v", snapshot.Groups)
		}
	}
}

func TestPreviewCommandsRejectInvalidPayload(t *testing.T) {
	runtime := &coreRuntime{state: coreStopped}
	for _, input := range []string{
		`{"type":"previewProxySnapshot","payload":{"configPath":""}}`,
		`{"type":"previewGroupDelay","payload":{"configPath":"x","group":"","url":"https://example.com"}}`,
	} {
		response := decodeTestCommandResponse(t, runtime.executeCommand(input))
		if response.OK || response.Code != "INVALID_ARGUMENT" {
			t.Fatalf("unexpected preview validation response: %+v", response)
		}
	}
}

func TestNormalizeDelayRequest(t *testing.T) {
	url, timeout, err := normalizeDelayRequest("https://example.com", 100)
	if err != nil || url != "https://example.com" || timeout != 1000 {
		t.Fatalf("unexpected normalized request: %s %d %v", url, timeout, err)
	}
	_, timeout, err = normalizeDelayRequest("http://example.com", 20000)
	if err != nil || timeout != 10000 {
		t.Fatalf("unexpected max timeout: %d %v", timeout, err)
	}
	if _, _, err = normalizeDelayRequest("ftp://example.com", 5000); err == nil {
		t.Fatal("expected invalid scheme error")
	}
}

func TestClassifyDelayError(t *testing.T) {
	tests := []struct {
		err  error
		want string
	}{
		{context.DeadlineExceeded, "TIMEOUT"},
		{errors.New("lookup example.com: no such host"), "DNS"},
		{errors.New("tls: failed to verify certificate"), "TLS"},
		{errors.New("outbound socket protect failed"), "PROTECT"},
		{errors.New("connect: network is unreachable"), "CONNECT"},
		{errors.New("unexpected failure"), "UNKNOWN"},
		{nil, "UNKNOWN"},
	}
	for _, test := range tests {
		if got := classifyDelayError(test.err); got != test.want {
			t.Fatalf("classifyDelayError(%v) = %s, want %s", test.err, got, test.want)
		}
	}
}

func TestDelayProgressReporterEmitsTypedPayload(t *testing.T) {
	if groupDelayConcurrency != 8 {
		t.Fatalf("unexpected group delay concurrency: %d", groupDelayConcurrency)
	}
	defer setCoreEventHandler(nil)
	var eventType coreEventType
	var state coreRuntimeState
	var message string
	setCoreEventHandler(func(currentType coreEventType, currentState coreRuntimeState,
		_ coreErrorCode, currentMessage string) {
		eventType = currentType
		state = currentState
		message = currentMessage
	})
	reporter := buildDelayProgressReporter("operation-1234", "Auto", coreRunning)
	if reporter == nil {
		t.Fatal("expected delay progress reporter")
	}
	reporter(proxyDelayResult{Proxy: "Node A", Delay: -1, Alive: false, ErrorCode: "TIMEOUT"})
	if eventType != coreEventProxyDelayProgress || state != coreRunning {
		t.Fatalf("unexpected progress event: type=%v state=%v", eventType, state)
	}
	var progress proxyDelayProgress
	if err := json.Unmarshal([]byte(message), &progress); err != nil {
		t.Fatalf("invalid progress JSON: %v", err)
	}
	if progress.OperationID != "operation-1234" || progress.Group != "Auto" ||
		progress.Proxy != "Node A" || progress.Delay != -1 || progress.Alive ||
		progress.ErrorCode != "TIMEOUT" {
		t.Fatalf("unexpected progress payload: %+v", progress)
	}
	if buildDelayProgressReporter("", "Auto", coreRunning) != nil {
		t.Fatal("empty operation id must disable progress events")
	}
}

func TestExternalConfigWhenRequested(t *testing.T) {
	path := strings.TrimSpace(os.Getenv("NLASH_TEST_CONFIG_PATH"))
	if path == "" {
		t.Skip("NLASH_TEST_CONFIG_PATH is not set")
	}
	C.SetHomeDir(filepath.Dir(path))
	C.SetConfig(path)
	if _, err := parseConfigWithPath(path); err != nil {
		t.Fatalf("external configuration parse failed: %s", sanitizeCoreError(err))
	}
}

func TestApplyHarmonyGeoMirrorsPreservesCustomValues(t *testing.T) {
	raw, err := config.UnmarshalRawConfig([]byte("mixed-port: 7890\nrules: [MATCH,DIRECT]\n"))
	if err != nil {
		t.Fatal(err)
	}
	applyHarmonyGeoMirrors(raw)
	if raw.GeoXUrl.Mmdb != mirrorGeoBaseURL+"geoip.metadb" {
		t.Fatalf("unexpected MMDB mirror: %s", raw.GeoXUrl.Mmdb)
	}
	raw.GeoXUrl.Mmdb = "https://example.com/custom.mmdb"
	applyHarmonyGeoMirrors(raw)
	if raw.GeoXUrl.Mmdb != "https://example.com/custom.mmdb" {
		t.Fatal("custom MMDB address must be preserved")
	}
}

func TestConfigHomeDirSharesRuntimeDataForProfiles(t *testing.T) {
	profilePath := filepath.Join("data", "files", "profiles", "sample.yaml")
	want := filepath.Join("data", "files", "core", "work")
	if got := configHomeDir(profilePath); got != want {
		t.Fatalf("configHomeDir() = %q, want %q", got, want)
	}

	standalonePath := filepath.Join("tmp", "sample.yaml")
	if got := configHomeDir(standalonePath); got != filepath.Join("tmp") {
		t.Fatalf("standalone configHomeDir() = %q", got)
	}
}

func TestExecuteCommandRejectsUnsupportedCommand(t *testing.T) {
	runtime := &coreRuntime{state: coreRunning}
	response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"notSupported"}`))
	if response.OK || response.Code != "UNSUPPORTED" {
		t.Fatalf("unexpected unsupported response: %+v", response)
	}
}

func TestBusinessCommandsShareRuntimeReadLock(t *testing.T) {
	runtime := &coreRuntime{state: coreStopped}
	runtime.mu.RLock()
	done := make(chan string, 1)
	go func() {
		done <- runtime.executeCommand(`{"type":"dashboardSnapshot"}`)
	}()
	select {
	case response := <-done:
		if decoded := decodeTestCommandResponse(t, response); decoded.Code != "CORE_NOT_RUNNING" {
			t.Fatalf("unexpected concurrent response: %+v", decoded)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("business command was serialized behind another reader")
	}
	runtime.mu.RUnlock()
}

func TestLifecycleCommandsRemainExclusive(t *testing.T) {
	runtime := &coreRuntime{state: coreStopped}
	runtime.mu.RLock()
	done := make(chan coreErrorCode, 1)
	go func() {
		done <- runtime.stop()
	}()
	select {
	case <-done:
		t.Fatal("lifecycle command must wait for active business readers")
	case <-time.After(50 * time.Millisecond):
	}
	runtime.mu.RUnlock()
	select {
	case code := <-done:
		if code != coreOK {
			t.Fatalf("unexpected stop code: %v", code)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("lifecycle command did not resume after readers completed")
	}
}

func decodeTestCommandResponse(t *testing.T, raw string) coreCommandResponse {
	t.Helper()
	var response coreCommandResponse
	if err := json.Unmarshal([]byte(raw), &response); err != nil {
		t.Fatalf("invalid command response JSON: %v", err)
	}
	return response
}
