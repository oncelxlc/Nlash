package main

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	coreDNS "github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/listener/inner"
	D "github.com/miekg/dns"
)

func TestDNSHistoryCopiesBoundsAndClearsRecords(t *testing.T) {
	var history dnsQueryHistory
	history.setEnabled(true)
	start := time.Now()
	message := &D.Msg{Answer: []D.RR{&D.A{A: net.ParseIP("192.0.2.1")}}}
	for i := 0; i < maxDNSHistory+10; i++ {
		history.append(coreDNS.QueryRecord{Question: D.Question{Name: "example.com.", Qtype: D.TypeA},
			Msg: message, Start: start.Add(time.Duration(i) * time.Millisecond), Cached: true, Initiator: "direct"})
	}
	message.Answer[0].(*D.A).A = net.ParseIP("192.0.2.2")
	snapshot := history.snapshot()
	if len(snapshot) != maxDNSHistory || snapshot[0].ID != "209" || snapshot[0].Host != "example.com" ||
		snapshot[0].Answers[0] != "192.0.2.1" || snapshot[0].Duration != 0 || snapshot[0].Type != "A" {
		t.Fatalf("unexpected query snapshot: %+v", snapshot[0])
	}
	snapshot[0].Answers[0] = "changed"
	if history.snapshot()[0].Answers[0] != "192.0.2.1" {
		t.Fatal("snapshot aliases history")
	}
	history.setEnabled(true)
	history.append(coreDNS.QueryRecord{Start: start.Add(-time.Hour)})
	if len(history.snapshot()) != 0 {
		t.Fatal("stale query crossed core sessions")
	}
}

func TestDNSHistoryReportsFailuresAndBoundsPayload(t *testing.T) {
	var history dnsQueryHistory
	history.setEnabled(true)
	history.append(coreDNS.QueryRecord{Question: D.Question{Name: "missing.example.", Qtype: 65000},
		Start: time.Now(), Err: errors.New("private upstream failure")})
	if record := history.snapshot()[0]; record.Error == "" || strings.Contains(record.Error, "private") || record.Type != "TYPE65000" {
		t.Fatalf("unexpected error record: %+v", record)
	}
	answers := []D.RR{}
	for i := 0; i < 30; i++ {
		answers = append(answers, &D.TXT{Txt: []string{strings.Repeat("\"", 500)}})
	}
	for i := 0; i < maxDNSHistory; i++ {
		history.append(coreDNS.QueryRecord{Question: D.Question{Name: strings.Repeat("a", 250), Qtype: D.TypeTXT},
			Msg: &D.Msg{Answer: answers}, Start: time.Now(), Upstream: strings.Repeat("\"", 2000)})
	}
	payload, err := json.Marshal(history.snapshot())
	if err != nil || len(payload) >= 1024*1024 {
		t.Fatalf("DNS response exceeds IPC boundary: %d, %v", len(payload), err)
	}
}

func TestDNSHistoryOnlyRecordsCurrentProxySession(t *testing.T) {
	var history dnsQueryHistory
	history.append(coreDNS.QueryRecord{Start: time.Now()})
	if len(history.snapshot()) != 0 {
		t.Fatal("recorded DNS before proxy was enabled")
	}
	history.setEnabled(true)
	oldQuery := coreDNS.QueryRecord{Start: time.Now()}
	history.append(oldQuery)
	if len(history.snapshot()) != 1 {
		t.Fatal("did not record active proxy DNS")
	}
	// Windows 的时钟粒度可能让紧邻的开启和关闭得到同一时间戳。
	time.Sleep(20 * time.Millisecond)
	history.setEnabled(false)
	history.append(coreDNS.QueryRecord{Start: time.Now()})
	if len(history.snapshot()) != 0 || history.records[0].ID != "" {
		t.Fatal("disabled proxy retained or collected DNS records")
	}
	history.setEnabled(true)
	history.append(oldQuery)
	if len(history.snapshot()) != 0 {
		t.Fatal("late DNS response leaked into the next proxy session")
	}
	history.append(coreDNS.QueryRecord{Start: time.Now()})
	if len(history.snapshot()) != 1 {
		t.Fatal("new proxy session did not resume recording")
	}
}

func TestGeoSettingsValidationAndAtomicPersistence(t *testing.T) {
	for _, address := range []string{"file:///tmp/data", "https://user:pass@example.com/data", "https://example.com/#token", "https://", "https://a:abc/data"} {
		if validateGeoSettings(geoSettings{URLs: map[string]string{"MMDB": address}}) == nil {
			t.Errorf("accepted %q", address)
		}
	}
	zero, fractionalRange := 0, 721
	for _, interval := range []*int{&zero, &fractionalRange} {
		if validateGeoSettings(geoSettings{IntervalHours: interval}) == nil {
			t.Error("accepted invalid interval")
		}
	}
	home := t.TempDir()
	path := filepath.Join(home, geoSettingsFile)
	if err := writeAtomic(path, []byte(`{"urls":{"MMDB":"https://example.com/custom.mmdb"},"autoUpdate":true,"intervalHours":12}`)); err != nil {
		t.Fatal(err)
	}
	raw, err := config.UnmarshalRawConfig([]byte("geo-auto-update: false\n"))
	if err != nil {
		t.Fatal(err)
	}
	originalASN := raw.GeoXUrl.ASN
	if err = applySavedGeoSettings(raw, home); err != nil {
		t.Fatal(err)
	}
	if raw.GeoXUrl.Mmdb != "https://example.com/custom.mmdb" || raw.GeoXUrl.ASN != originalASN || !raw.GeoAutoUpdate || raw.GeoUpdateInterval != 12 {
		t.Fatal("override lost untouched fields or was not applied")
	}
	if err = writeAtomic(path, []byte(`{"urls":{}}`)); err != nil {
		t.Fatal(err)
	}
	files, _ := filepath.Glob(filepath.Join(home, ".nlash-geo-*"))
	if len(files) != 0 {
		t.Fatal("temporary resource files leaked")
	}
}

func TestInvalidGeoDownloadPreservesExistingFiles(t *testing.T) {
	previousTunnel := inner.GetTunnel()
	inner.New(nil)
	defer inner.New(previousTunnel)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("not a database")) }))
	defer server.Close()
	home := t.TempDir()
	previousHome := C.Path.HomeDir()
	C.SetHomeDir(home)
	defer C.SetHomeDir(previousHome)
	settings := geoSettings{URLs: map[string]string{"MMDB": server.URL, "ASN": server.URL, "GEOIP": server.URL, "GEOSITE": server.URL}}
	data, _ := json.Marshal(settings)
	if err := writeAtomic(filepath.Join(home, geoSettingsFile), data); err != nil {
		t.Fatal(err)
	}
	runtime := &coreRuntime{state: coreRunning, configData: []byte("geo-auto-update: false\n"), workDir: home, geoContext: context.Background()}
	snapshot, err := runtime.resourceSnapshot()
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range snapshot.Resources {
		if err := os.WriteFile(item.Path, []byte("previous database"), 0600); err != nil {
			t.Fatal(err)
		}
	}
	if response := runtime.updateGeoResources(0); response.OK || response.Code != "UPDATE_FAILED" {
		t.Fatalf("unexpected result: %+v", response)
	}
	if runtime.geoUpdating.Load() {
		t.Fatal("update stayed busy")
	}
	for _, item := range snapshot.Resources {
		data, err := os.ReadFile(item.Path)
		if err != nil || string(data) != "previous database" {
			t.Fatalf("old %s file lost: %v", item.Kind, err)
		}
	}
}

func TestGeoDownloadDoesNotBlockLifecycleAndCancels(t *testing.T) {
	previousTunnel := inner.GetTunnel()
	inner.New(nil)
	defer inner.New(previousTunnel)
	entered := make(chan struct{}, 1)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		select {
		case entered <- struct{}{}:
		default:
		}
		<-r.Context().Done()
	}))
	defer server.Close()
	home := t.TempDir()
	previousHome := C.Path.HomeDir()
	C.SetHomeDir(home)
	defer C.SetHomeDir(previousHome)
	data, _ := json.Marshal(geoSettings{URLs: map[string]string{"MMDB": server.URL}})
	if err := writeAtomic(filepath.Join(home, geoSettingsFile), data); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	runtime := &coreRuntime{state: coreRunning, workDir: home, configData: []byte("geo-auto-update: false\n"), geoContext: ctx}
	done := make(chan coreCommandResponse, 1)
	go func() { done <- runtime.updateGeoResources(0) }()
	select {
	case <-entered:
	case <-time.After(3 * time.Second):
		t.Fatal("download never started")
	}
	if !runtime.mu.TryLock() {
		t.Fatal("network download held lifecycle lock")
	}
	runtime.state = coreStopped
	cancel()
	runtime.mu.Unlock()
	select {
	case response := <-done:
		if response.OK || response.Code != "CANCELLED" {
			t.Fatalf("unexpected result: %+v", response)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("download did not cancel")
	}
}

func TestGeoUpdatesRejectStaleTimersAndPersistSettings(t *testing.T) {
	home := t.TempDir()
	previousHome := C.Path.HomeDir()
	C.SetHomeDir(home)
	defer C.SetHomeDir(previousHome)
	runtime := &coreRuntime{state: coreRunning, workDir: home, configData: []byte("geo-auto-update: false\n"), geoGeneration: 2}
	if response := runtime.updateGeoResources(1); response.OK {
		t.Fatal("stale timer started a download")
	}
	if runtime.geoUpdating.Load() {
		t.Fatal("stale timer left resource updating")
	}
	response := runtime.saveGeoSettings(json.RawMessage(`{"autoUpdate":true,"intervalHours":12}`))
	if !response.OK || runtime.geoTimer == nil {
		t.Fatalf("could not enable automatic updates: %+v", response)
	}
	first := runtime.geoContext
	defer runtime.geoCancel()
	response = runtime.saveGeoSettings(json.RawMessage(`{"urls":{"MMDB":"https://example.com/custom.mmdb"}}`))
	if !response.OK || first.Err() == nil {
		t.Fatal("settings change did not cancel the old update generation")
	}
	settings, err := readGeoSettings(home)
	if err != nil || settings.AutoUpdate == nil || !*settings.AutoUpdate || settings.IntervalHours == nil || *settings.IntervalHours != 12 || settings.URLs["MMDB"] == "" {
		t.Fatalf("patch lost settings: %+v, %v", settings, err)
	}
	response = runtime.saveGeoSettings(json.RawMessage(`{"autoUpdate":false}`))
	if !response.OK || runtime.geoTimer != nil {
		t.Fatal("disabling updates left a scheduled timer")
	}
}
