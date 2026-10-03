package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	P "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/tunnel"
	"github.com/metacubex/mihomo/tunnel/statistic"
)

const maxCoreCommandBytes = 16 * 1024
const groupDelayConcurrency = 8

type coreCommand struct {
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload,omitempty"`
}

type coreCommandResponse struct {
	OK      bool   `json:"ok"`
	Code    string `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

type dashboardSnapshot struct {
	Mode            string `json:"mode"`
	UploadSpeed     int64  `json:"uploadSpeed"`
	DownloadSpeed   int64  `json:"downloadSpeed"`
	UploadTotal     int64  `json:"uploadTotal"`
	DownloadTotal   int64  `json:"downloadTotal"`
	MemoryBytes     uint64 `json:"memoryBytes"`
	ConnectionCount int    `json:"connectionCount"`
}

type proxyNodeSnapshot struct {
	Name   string `json:"name"`
	Type   string `json:"type"`
	Alive  bool   `json:"alive"`
	Tested bool   `json:"tested"`
	Delay  int32  `json:"delay"`
	UDP    bool   `json:"udp"`
}

type proxyGroupSnapshot struct {
	Name       string              `json:"name"`
	Type       string              `json:"type"`
	Selected   string              `json:"selected"`
	Selectable bool                `json:"selectable"`
	Hidden     bool                `json:"hidden"`
	Nodes      []proxyNodeSnapshot `json:"nodes"`
}

type proxySnapshot struct {
	Source string               `json:"source"`
	Mode   string               `json:"mode"`
	Groups []proxyGroupSnapshot `json:"groups"`
}

var previewParseMutex sync.Mutex

type previewProxyPayload struct {
	ConfigPath string `json:"configPath"`
}

type previewGroupDelayPayload struct {
	ConfigPath  string `json:"configPath"`
	Group       string `json:"group"`
	Proxy       string `json:"proxy,omitempty"`
	URL         string `json:"url"`
	Timeout     int64  `json:"timeout"`
	OperationID string `json:"operationId,omitempty"`
}

type groupDelayPayload struct {
	Group       string `json:"group"`
	Proxy       string `json:"proxy,omitempty"`
	URL         string `json:"url"`
	Timeout     int64  `json:"timeout"`
	OperationID string `json:"operationId,omitempty"`
}

type proxyDelayResult struct {
	Proxy     string `json:"proxy"`
	Delay     int32  `json:"delay"`
	Alive     bool   `json:"alive"`
	ErrorCode string `json:"errorCode,omitempty"`
}

type groupDelayResult struct {
	Group   string             `json:"group"`
	Results []proxyDelayResult `json:"results"`
}

type proxyDelayProgress struct {
	OperationID string `json:"operationId"`
	Group       string `json:"group"`
	Proxy       string `json:"proxy"`
	Delay       int32  `json:"delay"`
	Alive       bool   `json:"alive"`
	ErrorCode   string `json:"errorCode,omitempty"`
}

type connectionSnapshot struct {
	ID          string   `json:"id"`
	Network     string   `json:"network"`
	Type        string   `json:"type"`
	Host        string   `json:"host"`
	Destination string   `json:"destination"`
	Source      string   `json:"source"`
	Process     string   `json:"process,omitempty"`
	Start       int64    `json:"start"`
	Upload      int64    `json:"upload"`
	Download    int64    `json:"download"`
	Chains      []string `json:"chains"`
	Rule        string   `json:"rule"`
	RulePayload string   `json:"rulePayload"`
}

type connectionsSnapshot struct {
	UploadTotal   int64                `json:"uploadTotal"`
	DownloadTotal int64                `json:"downloadTotal"`
	MemoryBytes   uint64               `json:"memoryBytes"`
	Connections   []connectionSnapshot `json:"connections"`
}

type selectProxyPayload struct {
	Group string `json:"group"`
	Proxy string `json:"proxy"`
}

type delayTestPayload struct {
	Proxy   string `json:"proxy"`
	URL     string `json:"url"`
	Timeout int64  `json:"timeout"`
}

type closeConnectionPayload struct {
	ID string `json:"id"`
}

type setModePayload struct {
	Mode string `json:"mode"`
}

func (runtime *coreRuntime) executeCommand(raw string) string {
	if len(raw) == 0 || len(raw) > maxCoreCommandBytes {
		return marshalCommandResponse(commandFailure("INVALID_ARGUMENT", "command is empty or too large"))
	}
	var command coreCommand
	if err := json.Unmarshal([]byte(raw), &command); err != nil || command.Type == "" {
		return marshalCommandResponse(commandFailure("INVALID_ARGUMENT", "command is invalid"))
	}
	if command.Type == "applyConfig" {
		var payload previewProxyPayload
		if !decodeCommandPayload(command.Payload, &payload) || strings.TrimSpace(payload.ConfigPath) == "" {
			return marshalCommandResponse(commandFailure("INVALID_ARGUMENT", "configuration path is invalid"))
		}
		return marshalCommandResponse(runtime.applyConfig(payload.ConfigPath, false))
	}
	if command.Type == "rollbackConfig" {
		return marshalCommandResponse(runtime.applyConfig("", true))
	}
	runtime.mu.RLock()
	defer runtime.mu.RUnlock()
	if command.Type == "previewProxySnapshot" {
		var payload previewProxyPayload
		if !decodeCommandPayload(command.Payload, &payload) || strings.TrimSpace(payload.ConfigPath) == "" {
			return marshalCommandResponse(commandFailure("INVALID_ARGUMENT", "preview configuration is invalid"))
		}
		snapshot, err := previewProxySnapshot(payload.ConfigPath)
		if err != nil {
			return marshalCommandResponse(commandFailure("PREVIEW_FAILED", err.Error()))
		}
		return marshalCommandResponse(commandSuccess(snapshot))
	}
	if command.Type == "previewGroupDelay" {
		var payload previewGroupDelayPayload
		if !decodeCommandPayload(command.Payload, &payload) || strings.TrimSpace(payload.ConfigPath) == "" ||
			strings.TrimSpace(payload.Group) == "" {
			return marshalCommandResponse(commandFailure("INVALID_ARGUMENT", "preview delay request is invalid"))
		}
		result, err := previewGroupDelay(payload)
		if err != nil {
			return marshalCommandResponse(commandFailure("DELAY_FAILED", err.Error()))
		}
		return marshalCommandResponse(commandSuccess(result))
	}
	if runtime.state != coreRunning {
		return marshalCommandResponse(commandFailure("CORE_NOT_RUNNING", "core is not running"))
	}

	var response coreCommandResponse
	switch command.Type {
	case "dashboardSnapshot":
		response = commandSuccess(runtime.dashboardSnapshot())
	case "proxySnapshot":
		response = commandSuccess(runtime.proxySnapshot())
	case "connectionSnapshot":
		response = commandSuccess(runtime.connectionsSnapshot())
	case "selectProxy":
		var payload selectProxyPayload
		if !decodeCommandPayload(command.Payload, &payload) {
			response = commandFailure("INVALID_ARGUMENT", "proxy selection is invalid")
		} else if err := selectProxy(payload.Group, payload.Proxy); err != nil {
			response = commandFailure("SELECT_FAILED", err.Error())
		} else {
			response = commandSuccess(nil)
		}
	case "testDelay":
		var payload delayTestPayload
		if !decodeCommandPayload(command.Payload, &payload) {
			response = commandFailure("INVALID_ARGUMENT", "delay test is invalid")
		} else if delay, err := testProxyDelay(payload); err != nil {
			response = commandFailure("DELAY_FAILED", err.Error())
		} else {
			response = commandSuccess(map[string]any{"proxy": payload.Proxy, "delay": delay})
		}
	case "testGroupDelay":
		var payload groupDelayPayload
		if !decodeCommandPayload(command.Payload, &payload) || strings.TrimSpace(payload.Group) == "" {
			response = commandFailure("INVALID_ARGUMENT", "group delay test is invalid")
		} else if result, err := testRuntimeGroupDelay(payload); err != nil {
			response = commandFailure("DELAY_FAILED", err.Error())
		} else {
			response = commandSuccess(result)
		}
	case "closeConnection":
		var payload closeConnectionPayload
		if !decodeCommandPayload(command.Payload, &payload) || payload.ID == "" {
			response = commandFailure("INVALID_ARGUMENT", "connection id is invalid")
		} else if tracker := statistic.DefaultManager.Get(payload.ID); tracker == nil {
			response = commandFailure("NOT_FOUND", "connection was not found")
		} else if err := tracker.Close(); err != nil {
			response = commandFailure("CLOSE_FAILED", "connection close failed")
		} else {
			response = commandSuccess(nil)
		}
	case "closeAllConnections":
		closeAllConnections()
		response = commandSuccess(nil)
	case "setMode":
		var payload setModePayload
		if !decodeCommandPayload(command.Payload, &payload) {
			response = commandFailure("INVALID_ARGUMENT", "mode is invalid")
		} else if mode, ok := tunnel.ModeMapping[strings.ToLower(payload.Mode)]; !ok {
			response = commandFailure("INVALID_ARGUMENT", "mode is unsupported")
		} else {
			tunnel.SetMode(mode)
			response = commandSuccess(map[string]any{"mode": mode.String()})
		}
	case "resetTraffic":
		statistic.DefaultManager.ResetStatistic()
		response = commandSuccess(nil)
	default:
		response = commandFailure("UNSUPPORTED", "command is unsupported")
	}
	return marshalCommandResponse(response)
}

func restoreProxySnapshot(snapshot proxySnapshot) error {
	mode, ok := tunnel.ModeMapping[strings.ToLower(snapshot.Mode)]
	if !ok {
		return errors.New("previous mode is invalid")
	}
	tunnel.SetMode(mode)
	for _, group := range snapshot.Groups {
		if group.Selectable && group.Selected != "" {
			if err := selectProxy(group.Name, group.Selected); err != nil {
				return err
			}
		}
	}
	return nil
}

func (runtime *coreRuntime) dashboardSnapshot() dashboardSnapshot {
	uploadSpeed, downloadSpeed := statistic.DefaultManager.Now()
	uploadTotal, downloadTotal := statistic.DefaultManager.Total()
	connectionCount := 0
	statistic.DefaultManager.Range(func(statistic.Tracker) bool {
		connectionCount++
		return true
	})
	return dashboardSnapshot{
		Mode:            tunnel.Mode().String(),
		UploadSpeed:     uploadSpeed,
		DownloadSpeed:   downloadSpeed,
		UploadTotal:     uploadTotal,
		DownloadTotal:   downloadTotal,
		MemoryBytes:     statistic.DefaultManager.Memory(),
		ConnectionCount: connectionCount,
	}
}

func (runtime *coreRuntime) proxySnapshot() proxySnapshot {
	return buildProxySnapshot(tunnel.Proxies(), runtime.proxyGroupOrder, "runtime", tunnel.Mode().String())
}

func buildProxySnapshot(proxies map[string]C.Proxy, preferredOrder []string, source string,
	mode string) proxySnapshot {
	groups := make([]proxyGroupSnapshot, 0)
	seen := make(map[string]bool)
	appendGroup := func(name string) {
		if seen[name] {
			return
		}
		seen[name] = true
		proxy := proxies[name]
		if proxy == nil {
			return
		}
		group, ok := proxy.Adapter().(outboundgroup.ProxyGroup)
		if !ok {
			return
		}
		_, selectable := proxy.Adapter().(outboundgroup.SelectAble)
		nodes := make([]proxyNodeSnapshot, 0)
		for _, node := range group.Proxies() {
			delay := int32(-1)
			history := node.DelayHistory()
			tested := len(history) > 0
			if len(history) > 0 && history[len(history)-1].Delay > 0 {
				delay = int32(history[len(history)-1].Delay)
			}
			nodes = append(nodes, proxyNodeSnapshot{
				Name:   node.Name(),
				Type:   node.Type().String(),
				Alive:  tested && node.AliveForTestUrl(C.DefaultTestURL),
				Tested: tested,
				Delay:  delay,
				UDP:    node.SupportUDP(),
			})
		}
		groups = append(groups, proxyGroupSnapshot{
			Name:       name,
			Type:       proxy.Type().String(),
			Selected:   group.Now(),
			Selectable: selectable,
			Hidden:     group.Hidden(),
			Nodes:      nodes,
		})
	}
	for _, name := range preferredOrder {
		appendGroup(name)
	}
	remaining := make([]string, 0)
	for name := range proxies {
		if !seen[name] {
			remaining = append(remaining, name)
		}
	}
	sort.Strings(remaining)
	for _, name := range remaining {
		appendGroup(name)
	}
	return proxySnapshot{Source: source, Mode: mode, Groups: groups}
}

type closeableProvider interface {
	Close() error
}

func parsePreviewConfig(configPath string) (*config.Config, []string, func(), error) {
	previewParseMutex.Lock()
	defer previewParseMutex.Unlock()
	cleanPath := strings.TrimSpace(configPath)
	if cleanPath == "" {
		return nil, nil, func() {}, errors.New("configuration path is empty")
	}
	data, err := os.ReadFile(cleanPath)
	if err != nil {
		return nil, nil, func() {}, errors.New("configuration file cannot be read")
	}
	raw, err := config.UnmarshalRawConfig(data)
	if err != nil {
		return nil, nil, func() {}, errors.New("configuration is invalid")
	}
	applyHarmonyGeoMirrors(raw)
	order := rawProxyGroupOrder(raw)
	homeDir, err := prepareConfigHome(cleanPath)
	if err != nil {
		return nil, nil, func() {}, errors.New("core work directory cannot be prepared")
	}
	C.SetHomeDir(homeDir)
	C.SetConfig(cleanPath)
	cfg, err := config.ParseRawConfig(raw)
	if err != nil {
		return nil, nil, func() {}, errors.New("configuration is invalid")
	}
	initialized := make([]P.ProxyProvider, 0, len(cfg.Providers))
	cleanup := func() {
		for _, provider := range initialized {
			if closeable, ok := provider.(closeableProvider); ok {
				_ = closeable.Close()
			}
		}
	}
	for _, provider := range cfg.Providers {
		if err = provider.Initial(); err != nil {
			cleanup()
			return nil, nil, func() {}, errors.New("proxy provider initialization failed")
		}
		initialized = append(initialized, provider)
	}
	return cfg, order, cleanup, nil
}

func previewProxySnapshot(configPath string) (proxySnapshot, error) {
	cfg, order, cleanup, err := parsePreviewConfig(configPath)
	if err != nil {
		return proxySnapshot{}, err
	}
	defer cleanup()
	return buildProxySnapshot(cfg.Proxies, order, "config", cfg.General.Mode.String()), nil
}

func previewGroupDelay(payload previewGroupDelayPayload) (groupDelayResult, error) {
	testURL, timeout, err := normalizeDelayRequest(payload.URL, payload.Timeout)
	if err != nil {
		return groupDelayResult{}, err
	}
	cfg, _, cleanup, err := parsePreviewConfig(payload.ConfigPath)
	if err != nil {
		return groupDelayResult{}, err
	}
	defer cleanup()
	proxy := cfg.Proxies[payload.Group]
	if proxy == nil {
		return groupDelayResult{}, errors.New("proxy group was not found")
	}
	group, ok := proxy.Adapter().(outboundgroup.ProxyGroup)
	if !ok {
		return groupDelayResult{}, errors.New("proxy group is invalid")
	}
	result := runGroupDelay(payload.Group, group.Proxies(), payload.Proxy, testURL, timeout,
		buildDelayProgressReporter(payload.OperationID, payload.Group, coreStopped))
	if payload.Proxy != "" && len(result.Results) == 0 {
		return groupDelayResult{}, errors.New("proxy was not found in group")
	}
	return result, nil
}

type indexedProxyDelayResult struct {
	index  int
	result proxyDelayResult
}

func runGroupDelay(groupName string, nodes []C.Proxy, proxyName string, testURL string,
	timeout int64, progress func(proxyDelayResult)) groupDelayResult {
	selected := make([]C.Proxy, 0, len(nodes))
	for _, node := range nodes {
		if proxyName == "" || node.Name() == proxyName {
			selected = append(selected, node)
		}
	}
	nodes = selected
	results := make([]proxyDelayResult, len(nodes))
	semaphore := make(chan struct{}, groupDelayConcurrency)
	completed := make(chan indexedProxyDelayResult, len(nodes))
	for index, node := range nodes {
		index := index
		node := node
		go func() {
			semaphore <- struct{}{}
			defer func() { <-semaphore }()
			ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Millisecond)
			defer cancel()
			testCompleted := make(chan proxyDelayResult, 1)
			go func() {
				expectedStatus, _ := utils.NewUnsignedRanges[uint16]("")
				delay, testErr := node.URLTest(ctx, testURL, expectedStatus)
				alive := testErr == nil && delay > 0
				value := int32(-1)
				errorCode := ""
				if alive {
					value = int32(delay)
				} else {
					errorCode = classifyDelayError(testErr)
				}
				testCompleted <- proxyDelayResult{
					Proxy: node.Name(), Delay: value, Alive: alive, ErrorCode: errorCode,
				}
			}()
			var result proxyDelayResult
			select {
			case result = <-testCompleted:
			case <-ctx.Done():
				result = proxyDelayResult{Proxy: node.Name(), Delay: -1, Alive: false, ErrorCode: "TIMEOUT"}
			}
			completed <- indexedProxyDelayResult{
				index:  index,
				result: result,
			}
		}()
	}
	for range nodes {
		completedResult := <-completed
		results[completedResult.index] = completedResult.result
		if progress != nil {
			progress(completedResult.result)
		}
	}
	return groupDelayResult{Group: groupName, Results: results}
}

func buildDelayProgressReporter(operationID string, groupName string,
	state coreRuntimeState) func(proxyDelayResult) {
	if strings.TrimSpace(operationID) == "" {
		return nil
	}
	return func(result proxyDelayResult) {
		mode := "preview"
		if state == coreRunning {
			mode = "runtime"
		}
		errorCode := result.ErrorCode
		if errorCode == "" {
			errorCode = "OK"
		}
		emitCoreEvent(coreEventLog, state, coreOK,
			fmt.Sprintf("delay operation=%s mode=%s errorCode=%s", operationID, mode, errorCode))
		payload, err := json.Marshal(proxyDelayProgress{
			OperationID: operationID,
			Group:       groupName,
			Proxy:       result.Proxy,
			Delay:       result.Delay,
			Alive:       result.Alive,
			ErrorCode:   result.ErrorCode,
		})
		if err == nil {
			emitCoreProgressEvent(state, string(payload))
		}
	}
}

func normalizeDelayRequest(value string, timeout int64) (string, int64, error) {
	testURL := strings.TrimSpace(value)
	if testURL == "" {
		testURL = C.DefaultTestURL
	}
	if !strings.HasPrefix(testURL, "https://") && !strings.HasPrefix(testURL, "http://") {
		return "", 0, errors.New("delay test url is invalid")
	}
	if timeout < 1000 {
		timeout = 1000
	}
	if timeout > 10000 {
		timeout = 10000
	}
	return testURL, timeout, nil
}

func (runtime *coreRuntime) connectionsSnapshot() connectionsSnapshot {
	snapshot := statistic.DefaultManager.Snapshot()
	connections := make([]connectionSnapshot, 0, len(snapshot.Connections))
	for _, tracker := range snapshot.Connections {
		if tracker == nil || tracker.Metadata == nil {
			continue
		}
		metadata := tracker.Metadata
		connections = append(connections, connectionSnapshot{
			ID:          tracker.UUID.String(),
			Network:     metadata.NetWork.String(),
			Type:        metadata.Type.String(),
			Host:        metadata.Host,
			Destination: metadata.RemoteAddress(),
			Source:      metadata.SourceAddress(),
			Process:     metadata.Process,
			Start:       tracker.Start.UnixMilli(),
			Upload:      tracker.UploadTotal.Load(),
			Download:    tracker.DownloadTotal.Load(),
			Chains:      append([]string(nil), tracker.Chain...),
			Rule:        tracker.Rule,
			RulePayload: tracker.RulePayload,
		})
	}
	sort.SliceStable(connections, func(left, right int) bool {
		return connections[left].Start > connections[right].Start
	})
	return connectionsSnapshot{
		UploadTotal:   snapshot.UploadTotal,
		DownloadTotal: snapshot.DownloadTotal,
		MemoryBytes:   snapshot.Memory,
		Connections:   connections,
	}
}

func selectProxy(groupName string, proxyName string) error {
	if groupName == "" || proxyName == "" {
		return errors.New("proxy selection is empty")
	}
	groupProxy := tunnel.Proxies()[groupName]
	if groupProxy == nil {
		return errors.New("proxy group was not found")
	}
	selector, ok := groupProxy.Adapter().(outboundgroup.SelectAble)
	if !ok {
		return errors.New("proxy group is not selectable")
	}
	if err := selector.Set(proxyName); err != nil {
		return errors.New("proxy was not found in group")
	}
	closeAllConnections()
	return nil
}

func closeAllConnections() {
	statistic.DefaultManager.Range(func(tracker statistic.Tracker) bool {
		_ = tracker.Close()
		return true
	})
}

func testProxyDelay(payload delayTestPayload) (int32, error) {
	proxy := tunnel.Proxies()[payload.Proxy]
	if proxy == nil {
		return -1, errors.New("proxy was not found")
	}
	testURL, timeout, err := normalizeDelayRequest(payload.URL, payload.Timeout)
	if err != nil {
		return -1, err
	}
	expectedStatus, _ := utils.NewUnsignedRanges[uint16]("")
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeout)*time.Millisecond)
	defer cancel()
	delay, err := proxy.URLTest(ctx, testURL, expectedStatus)
	if err != nil || delay == 0 {
		return -1, &delayTestError{code: classifyDelayError(err)}
	}
	return int32(delay), nil
}

type delayTestError struct {
	code string
}

func (failure *delayTestError) Error() string {
	return fmt.Sprintf("delay test failed (%s)", failure.code)
}

func classifyDelayError(err error) string {
	if err == nil {
		return "UNKNOWN"
	}
	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, context.Canceled) {
		return "TIMEOUT"
	}
	message := strings.ToLower(err.Error())
	if strings.Contains(message, "deadline") || strings.Contains(message, "timeout") ||
		strings.Contains(message, "timed out") {
		return "TIMEOUT"
	}
	if strings.Contains(message, "protect") {
		return "PROTECT"
	}
	if strings.Contains(message, "lookup") || strings.Contains(message, "dns") ||
		strings.Contains(message, "no such host") {
		return "DNS"
	}
	if strings.Contains(message, "tls") || strings.Contains(message, "x509") ||
		strings.Contains(message, "certificate") {
		return "TLS"
	}
	if strings.Contains(message, "connect") || strings.Contains(message, "connection") ||
		strings.Contains(message, "network is unreachable") || strings.Contains(message, "no route") {
		return "CONNECT"
	}
	return "UNKNOWN"
}

func testRuntimeGroupDelay(payload groupDelayPayload) (groupDelayResult, error) {
	proxy := tunnel.Proxies()[payload.Group]
	if proxy == nil {
		return groupDelayResult{}, errors.New("proxy group was not found")
	}
	group, ok := proxy.Adapter().(outboundgroup.ProxyGroup)
	if !ok {
		return groupDelayResult{}, errors.New("proxy group is invalid")
	}
	testURL, timeout, err := normalizeDelayRequest(payload.URL, payload.Timeout)
	if err != nil {
		return groupDelayResult{}, err
	}
	result := runGroupDelay(payload.Group, group.Proxies(), payload.Proxy, testURL, timeout,
		buildDelayProgressReporter(payload.OperationID, payload.Group, coreRunning))
	if payload.Proxy != "" && len(result.Results) == 0 {
		return groupDelayResult{}, errors.New("proxy was not found in group")
	}
	return result, nil
}

func decodeCommandPayload(raw json.RawMessage, target any) bool {
	return len(raw) > 0 && json.Unmarshal(raw, target) == nil
}

func commandSuccess(data any) coreCommandResponse {
	return coreCommandResponse{OK: true, Code: "OK", Data: data}
}

func commandFailure(code string, message string) coreCommandResponse {
	return coreCommandResponse{OK: false, Code: code, Message: sanitizeCoreErrorText(message)}
}

func marshalCommandResponse(response coreCommandResponse) string {
	data, err := json.Marshal(response)
	if err != nil {
		return `{"ok":false,"code":"INTERNAL_ERROR","message":"response encoding failed"}`
	}
	return string(data)
}
