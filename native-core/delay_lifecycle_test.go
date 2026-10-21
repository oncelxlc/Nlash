package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/metacubex/mihomo/component/profile/cachefile"
)

// writeDelayLifecycleConfig 故意开启组与 provider 的自动检查，验证宿主适配会将其暂停。
func writeDelayLifecycleConfig(t *testing.T, testURL string) (string, string) {
	t.Helper()
	dir := t.TempDir()
	writeTestGeneralSettings(t, dir)
	if err := os.WriteFile(filepath.Join(dir, "nodes.yaml"), []byte("proxies:\n  - name: imported\n    type: direct\n"), 0600); err != nil {
		t.Fatal(err)
	}
	data := fmt.Sprintf(`port: 0
socks-port: 0
mixed-port: 0
external-controller: ''
dns: {enable: false}
tun: {enable: false}
proxy-providers:
  Imported:
    type: file
    path: nodes.yaml
    health-check: {enable: true, url: '%s/provider', interval: 1}
proxy-groups:
  - name: Route
    type: select
    proxies: [DIRECT, REJECT]
  - name: Automatic
    type: url-test
    proxies: [DIRECT]
    url: '%s'
    interval: 1
  - name: ProviderGroup
    type: url-test
    use: [Imported]
    url: '%s/group'
    interval: 1
rules: ['MATCH,Route']
`, testURL, testURL, testURL)
	path := filepath.Join(dir, "profile.yaml")
	if err := os.WriteFile(path, []byte(data), 0600); err != nil {
		t.Fatal(err)
	}
	return dir, path
}

// closeDelayTestRuntime 释放 Mihomo 全局缓存数据库，避免测试间残留文件锁。
func closeDelayTestRuntime(runtime *coreRuntime) {
	runtime.stop()
	if cachefile.Cache().DB != nil {
		_ = cachefile.Cache().Close()
	}
}

func TestOpeningConfigurationDoesNotStartDelayQueries(t *testing.T) {
	requests := make(chan struct{}, 32)
	server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		requests <- struct{}{}
		writer.WriteHeader(http.StatusNoContent)
	}))
	defer server.Close()
	dir, path := writeDelayLifecycleConfig(t, server.URL)
	runtime := &coreRuntime{state: coreStopped}
	defer closeDelayTestRuntime(runtime)
	command, _ := json.Marshal(map[string]any{"type": "previewProxySnapshot", "payload": map[string]any{"configPath": path}})
	if response := decodeTestCommandResponse(t, runtime.executeCommand(string(command))); !response.OK {
		t.Fatalf("preview failed: %+v", response)
	}
	if code := runtime.start(coreStartOptions{configPath: path, workDir: dir}); code != coreOK {
		t.Fatalf("start failed: %v %s", code, runtime.lastError)
	}
	select {
	case <-requests:
		t.Fatal("opening a configuration started an automatic delay query")
	case <-time.After(150 * time.Millisecond):
	}
	command, _ = json.Marshal(map[string]any{"type": "testGroupDelay", "payload": groupDelayPayload{
		Group: "Route", Proxy: "DIRECT", URL: server.URL, Timeout: 1000,
	}})
	if response := decodeTestCommandResponse(t, runtime.executeCommand(string(command))); !response.OK {
		t.Fatalf("manual delay query failed: %+v", response)
	}
	select {
	case <-requests:
	case <-time.After(time.Second):
		t.Fatal("manual delay query did not reach the server")
	}
	cfg, err := runtime.parseActiveConfig(true)
	if err != nil {
		t.Fatal(err)
	}
	provider := cfg.Providers["Automatic"]
	defer provider.(closeableProvider).Close()
	if err = provider.Initial(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-requests:
	case <-time.After(time.Second):
		t.Fatal("enabling proxy did not restore configured health checks")
	}
}

func TestDelayQueriesDoNotBlockLifecycleOrSelection(t *testing.T) {
	for _, commandType := range []string{"previewGroupDelay", "testGroupDelay", "testDelay"} {
		t.Run(commandType, func(t *testing.T) {
			// 人为阻塞测速响应，确认生命周期和节点选择不需要等待网络请求结束。
			entered := make(chan struct{}, 1)
			release := make(chan struct{})
			var releaseOnce sync.Once
			unblock := func() { releaseOnce.Do(func() { close(release) }) }
			server := httptest.NewServer(http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
				entered <- struct{}{}
				<-release
				writer.WriteHeader(http.StatusNoContent)
			}))
			defer server.Close()
			defer unblock()
			dir, path := writeDelayLifecycleConfig(t, server.URL)
			runtime := &coreRuntime{state: coreStopped}
			defer closeDelayTestRuntime(runtime)
			if commandType != "previewGroupDelay" && runtime.start(coreStartOptions{configPath: path, workDir: dir}) != coreOK {
				t.Fatalf("start failed: %s", runtime.lastError)
			}
			command, _ := json.Marshal(map[string]any{"type": commandType, "payload": map[string]any{
				"configPath": path, "group": "Route", "proxy": "DIRECT", "url": server.URL, "timeout": 10000,
			}})
			delayDone := make(chan string, 1)
			go func() { delayDone <- runtime.executeCommand(string(command)) }()
			select {
			case <-entered:
			case <-time.After(2 * time.Second):
				t.Fatal("delay query did not start")
			}
			controlDone := make(chan error, 1)
			go func() {
				if commandType == "previewGroupDelay" && runtime.start(coreStartOptions{configPath: path, workDir: dir}) != coreOK {
					controlDone <- fmt.Errorf("start failed during preview delay")
					return
				}
				response := runtime.executeCommand(`{"type":"selectProxy","payload":{"group":"Route","proxy":"REJECT"}}`)
				var decoded coreCommandResponse
				if err := json.Unmarshal([]byte(response), &decoded); err != nil || !decoded.OK {
					controlDone <- fmt.Errorf("selection failed during delay: %s", response)
					return
				}
				if runtime.disableProxy() != coreOK || runtime.stop() != coreOK {
					controlDone <- fmt.Errorf("lifecycle failed during delay")
					return
				}
				controlDone <- nil
			}()
			select {
			case err := <-controlDone:
				if err != nil {
					t.Fatal(err)
				}
			case <-time.After(time.Second):
				unblock()
				<-controlDone
				t.Fatal("control operation waited for the delay query")
			}
			unblock()
			select {
			case <-delayDone:
			case <-time.After(2 * time.Second):
				t.Fatal("delay query did not complete")
			}
		})
	}
}
