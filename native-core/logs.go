package main

import (
	"fmt"
	"strings"
	"sync"
	"time"
	"unicode"
	"unicode/utf8"

	coreLog "github.com/metacubex/mihomo/log"
)

const (
	maxLogRecords = 500
	// JSON 转义后仍须留在跨进程响应的 1 MiB 限制内。
	maxLogBytes   = 64 * 1024
	maxLogMessage = 2048
)

type logRecord struct {
	ID      string `json:"id"`
	Time    int64  `json:"time"`
	Level   string `json:"level"`
	Message string `json:"message"`
}

type logSnapshot struct {
	Capture bool        `json:"capture"`
	Level   string      `json:"level"`
	Records []logRecord `json:"records"`
}

type coreLogHistory struct {
	mu      sync.Mutex
	records []logRecord
	bytes   int
	next    uint64
	capture bool
	level   coreLog.LogLevel
}

var logHistory = coreLogHistory{level: coreLog.INFO}

func init() {
	subscription := coreLog.Subscribe()
	go func() {
		for event := range subscription {
			logHistory.append(event)
		}
	}()
}

func (history *coreLogHistory) configure(settings generalSettings) {
	history.mu.Lock()
	defer history.mu.Unlock()
	history.capture = settings.LogCapture
	history.level = coreLog.LogLevelMapping[settings.LogLevel]
}

func (history *coreLogHistory) append(event coreLog.Event) {
	history.mu.Lock()
	defer history.mu.Unlock()
	if !history.capture || history.level == coreLog.SILENT || event.LogLevel < history.level {
		return
	}
	message := strings.Map(func(r rune) rune {
		if unicode.IsControl(r) {
			return ' '
		}
		return r
	}, event.Payload)
	if len(message) > maxLogMessage {
		message = message[:maxLogMessage]
		for !utf8.ValidString(message) {
			message = message[:len(message)-1]
		}
		message += "…"
	}
	history.next++
	history.records = append(history.records, logRecord{ID: fmt.Sprint(history.next),
		Time: time.Now().UnixMilli(), Level: event.LogLevel.String(), Message: message})
	history.bytes += len(message)
	for len(history.records) > maxLogRecords || history.bytes > maxLogBytes {
		history.bytes -= len(history.records[0].Message)
		history.records[0] = logRecord{}
		history.records = history.records[1:]
	}
}

func (history *coreLogHistory) snapshot() logSnapshot {
	history.mu.Lock()
	defer history.mu.Unlock()
	records := make([]logRecord, len(history.records))
	for index, record := range history.records {
		records[len(records)-1-index] = record
	}
	return logSnapshot{Capture: history.capture, Level: history.level.String(), Records: records}
}
