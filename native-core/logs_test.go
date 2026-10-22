package main

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	coreLog "github.com/metacubex/mihomo/log"
)

func TestLogCaptureFiltersLevelsAndClearsDisabledRecords(t *testing.T) {
	history := &coreLogHistory{}
	settings := defaultGeneralSettings()
	history.configure(settings)
	history.append(coreLog.Event{LogLevel: coreLog.ERROR, Payload: "disabled"})
	if len(history.snapshot().Records) != 0 {
		t.Fatal("capture must be opt-in")
	}
	settings.LogCapture, settings.LogLevel = true, "warning"
	history.configure(settings)
	for _, level := range []coreLog.LogLevel{coreLog.DEBUG, coreLog.INFO, coreLog.WARNING, coreLog.ERROR} {
		history.append(coreLog.Event{LogLevel: level, Payload: level.String()})
	}
	snapshot := history.snapshot()
	if !snapshot.Capture || snapshot.Level != "warning" || len(snapshot.Records) != 2 ||
		snapshot.Records[0].Level != "error" || snapshot.Records[1].Level != "warning" {
		t.Fatalf("unexpected levels or ordering: %+v", snapshot)
	}
	snapshot.Records[0].Message = "changed"
	settings.LogLevel = "silent"
	history.configure(settings)
	history.append(coreLog.Event{LogLevel: coreLog.ERROR, Payload: "silent"})
	if records := history.snapshot().Records; len(records) != 2 || records[0].Message != "error" {
		t.Fatal("level change changed existing records or snapshots shared storage")
	}
	settings.LogCapture = false
	history.configure(settings)
	history.append(coreLog.Event{LogLevel: coreLog.ERROR, Payload: "disabled"})
	if snapshot := history.snapshot(); snapshot.Capture || len(snapshot.Records) != 0 || history.bytes != 0 {
		t.Fatal("disabling capture did not clear records and byte accounting")
	}
	settings.LogCapture, settings.LogLevel = true, "debug"
	history.configure(settings)
	history.append(coreLog.Event{LogLevel: coreLog.DEBUG, Payload: "resumed"})
	if records := history.snapshot().Records; len(records) != 1 || records[0].Message != "resumed" || records[0].ID != "3" {
		t.Fatal("capture did not restart with fresh records and unique IDs")
	}
}

func TestLogHistoryBoundsMemoryAndResponseAndKeepsValidText(t *testing.T) {
	history := &coreLogHistory{}
	settings := defaultGeneralSettings()
	settings.LogCapture = true
	history.configure(settings)
	for range maxLogRecords + 10 {
		history.append(coreLog.Event{LogLevel: coreLog.INFO, Payload: "entry"})
	}
	if records := history.snapshot().Records; len(records) != maxLogRecords || records[len(records)-1].ID != "11" {
		t.Fatal("oldest logs were not evicted at the record limit")
	}
	for range maxLogRecords {
		history.append(coreLog.Event{LogLevel: coreLog.ERROR, Payload: strings.Repeat("<", maxLogMessage)})
	}
	if history.bytes > maxLogBytes || len(history.snapshot().Records) >= maxLogRecords {
		t.Fatal("log bytes were not bounded")
	}
	response := marshalCommandResponse(commandSuccess(history.snapshot()))
	envelope, err := json.Marshal(map[string]string{"response": response})
	if err != nil || len(envelope) >= 1024*1024 {
		t.Fatal("escaped log response exceeds control channel limit")
	}
	history.append(coreLog.Event{LogLevel: coreLog.INFO, Payload: "\n\r\x00" + strings.Repeat("日志🙂", 1000)})
	record := history.snapshot().Records[0]
	if !utf8.ValidString(record.Message) || len(record.Message) > maxLogMessage+3 ||
		strings.ContainsAny(record.Message, "\n\r\x00") || !strings.HasSuffix(record.Message, "…") || record.Time <= 0 {
		t.Fatal("truncated log text is invalid")
	}
}

func TestLogSettingsPersistWithoutReloadAndSubscribeToMihomo(t *testing.T) {
	dir := t.TempDir()
	writeTestGeneralSettings(t, dir)
	previousLevel := coreLog.Level()
	t.Cleanup(func() {
		logHistory.configure(defaultGeneralSettings())
		coreLog.SetLevel(previousLevel)
	})
	// An unreadable active profile proves a log-only save never reparses or reloads it.
	runtime := &coreRuntime{state: coreRunning, workDir: dir, configPath: filepath.Join(dir, "missing.yaml")}
	result := runtime.saveGeneralSettings(json.RawMessage(`{"logCapture":true,"logLevel":"debug"}`))
	if !result.OK || !runtime.general.LogCapture || coreLog.Level() != coreLog.DEBUG {
		t.Fatalf("log-only save attempted a reload: %+v", result)
	}
	saved, err := readGeneralSettings(dir)
	if err != nil || !saved.LogCapture || saved.LogLevel != "debug" {
		t.Fatal("log settings were not persisted")
	}
	marker := "nlash log subscription regression"
	coreLog.Debugln("%s", marker)
	deadline := time.Now().Add(time.Second)
	found := false
	for time.Now().Before(deadline) && !found {
		for _, record := range logHistory.snapshot().Records {
			found = found || record.Message == marker
		}
		if !found {
			time.Sleep(time.Millisecond)
		}
	}
	if !found {
		t.Fatal("Mihomo log was not captured")
	}
	runtime.state = coreStopped
	response := decodeTestCommandResponse(t, runtime.executeCommand(`{"type":"logSnapshot"}`))
	if !response.OK {
		t.Fatal("logs became unreadable after core stopped")
	}
	if result := runtime.saveGeneralSettings(json.RawMessage(`{"logCapture":false,"logLevel":"invalid"}`)); result.OK {
		t.Fatal("invalid log level was accepted")
	}
	if snapshot := logHistory.snapshot(); snapshot.Level != "debug" || !snapshot.Capture || len(snapshot.Records) == 0 {
		t.Fatal("failed save changed capture settings")
	}
	if result := runtime.saveGeneralSettings(json.RawMessage(`{"logCapture":false}`)); !result.OK {
		t.Fatalf("disabling capture failed: %+v", result)
	}
	if snapshot := logHistory.snapshot(); snapshot.Capture || len(snapshot.Records) != 0 {
		t.Fatal("saving disabled capture did not clear logs")
	}
	if saved, err := readGeneralSettings(dir); err != nil || saved.LogCapture {
		t.Fatal("disabled capture was not persisted")
	}
}
