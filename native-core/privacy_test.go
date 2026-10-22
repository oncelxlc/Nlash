package main

import (
	"errors"
	"net/netip"
	"path/filepath"
	"testing"
	"time"

	"github.com/metacubex/bbolt"
	"github.com/metacubex/mihomo/component/profile/cachefile"
	C "github.com/metacubex/mihomo/constant"
	coreDNS "github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

func TestProxyShutdownClearsActivityWhileCoreKeepsRunning(t *testing.T) {
	dir := t.TempDir()
	writeTestGeneralSettings(t, dir)
	previousHome := C.Path.HomeDir()
	t.Cleanup(func() { C.SetHomeDir(previousHome) })
	runtime := &coreRuntime{state: coreRunning, proxyEnabled: true, workDir: dir,
		configPath: filepath.Join(dir, "profile.yaml"), configData: []byte("dns: {enable: false}\nrules: ['MATCH,REJECT']\n")}
	t.Cleanup(func() { closeDelayTestRuntime(runtime) })
	dnsHistory.setEnabled(true)
	dnsHistory.append(coreDNS.QueryRecord{Start: time.Now()})
	tracker := &selectionTestTracker{}
	statistic.DefaultManager.Join(tracker)
	t.Cleanup(func() { statistic.DefaultManager.Leave(tracker) })
	statistic.DefaultManager.PushUploaded(false, 42)
	statistic.DefaultManager.PushDownloaded(false, 84)
	if code := runtime.disableProxy(); code != coreOK {
		t.Fatalf("disable failed: %v %s", code, runtime.lastError)
	}
	if runtime.state != coreRunning || runtime.proxyEnabled || !tracker.closed {
		t.Fatal("disable did not preserve core and close active connections")
	}
	if up, down := statistic.DefaultManager.Total(); up != 0 || down != 0 {
		t.Fatal("disable retained traffic totals")
	}
	dnsHistory.append(coreDNS.QueryRecord{Start: time.Now()})
	if len(dnsHistory.snapshot()) != 0 {
		t.Fatal("DNS collected while proxy disabled")
	}
	// Core-only work must not be exposed as proxy activity.
	statistic.DefaultManager.PushUploaded(false, 100)
	if snapshot := runtime.dashboardSnapshot(); snapshot.UploadTotal != 0 || snapshot.ConnectionCount != 0 {
		t.Fatal("disabled proxy exposed core-only counters")
	}
	if snapshot := runtime.connectionsSnapshot(); len(snapshot.Connections) != 0 || snapshot.UploadTotal != 0 {
		t.Fatal("disabled proxy exposed connection data")
	}
}

func TestCoreFailureClearsProxyActivity(t *testing.T) {
	dnsHistory.setEnabled(true)
	dnsHistory.append(coreDNS.QueryRecord{Start: time.Now()})
	statistic.DefaultManager.PushUploaded(false, 42)
	runtime := &coreRuntime{state: coreRunning, proxyEnabled: true}
	runtime.setFailure(coreInternalError, errors.New("test failure"))
	if len(dnsHistory.snapshot()) != 0 {
		t.Fatal("failed core retained DNS records")
	}
	if up, _ := statistic.DefaultManager.Total(); up != 0 {
		t.Fatal("failed core retained traffic totals")
	}
}

func TestProfileCannotPersistDNSMappings(t *testing.T) {
	previousHome := C.Path.HomeDir()
	C.SetHomeDir(t.TempDir())
	t.Cleanup(func() { C.SetHomeDir(previousHome) })
	settings := defaultGeneralSettings()
	for _, active := range []bool{false, true} {
		cfg, _, err := parseRuntimeConfigWithSettings([]byte("profile: {store-fake-ip: true}\ndns: {enable: false}\n"), active, settings, nil)
		if err != nil {
			t.Fatal(err)
		}
		if cfg.Profile.StoreFakeIP {
			t.Fatal("profile enabled persistent DNS mappings")
		}
	}
}

func TestClearsLegacyDNSWithoutDeletingOtherCacheData(t *testing.T) {
	db, err := bbolt.Open(filepath.Join(t.TempDir(), "cache.db"), 0600, nil)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	cache := &cachefile.CacheFile{DB: db}
	cache.FakeIpStore().PutByHost("legacy.example", netip.MustParseAddr("198.18.0.1"))
	cache.FakeIpStore6().PutByHost("legacy.example", netip.MustParseAddr("fdfe:dcba::1"))
	if err := db.Update(func(tx *bbolt.Tx) error {
		bucket, err := tx.CreateBucketIfNotExists([]byte("etag"))
		if err != nil {
			return err
		}
		return bucket.Put([]byte("subscription"), []byte("keep"))
	}); err != nil {
		t.Fatal(err)
	}
	if err := clearPersistedDNS(cache); err != nil {
		t.Fatal(err)
	}
	if _, exists := cache.FakeIpStore().GetByHost("legacy.example"); exists {
		t.Fatal("IPv4 DNS remained on disk")
	}
	if _, exists := cache.FakeIpStore6().GetByHost("legacy.example"); exists {
		t.Fatal("IPv6 DNS remained on disk")
	}
	if err := db.View(func(tx *bbolt.Tx) error {
		if string(tx.Bucket([]byte("etag")).Get([]byte("subscription"))) != "keep" {
			t.Fatal("unrelated cache data was deleted")
		}
		return nil
	}); err != nil {
		t.Fatal(err)
	}
}
