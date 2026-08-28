package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"

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
	if snapshot.Source != "config" || len(snapshot.Groups) < 2 || snapshot.Groups[0].Name != "First" ||
		len(snapshot.Groups[0].Nodes) != 2 || snapshot.Groups[0].Nodes[0].Tested {
		t.Fatalf("unexpected preview snapshot: %+v", snapshot)
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

func decodeTestCommandResponse(t *testing.T, raw string) coreCommandResponse {
	t.Helper()
	var response coreCommandResponse
	if err := json.Unmarshal([]byte(raw), &response); err != nil {
		t.Fatalf("invalid command response JSON: %v", err)
	}
	return response
}
