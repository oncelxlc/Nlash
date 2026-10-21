package main

import (
	"bytes"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net"
	"net/netip"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/component/trie"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	coreLog "github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
)

const generalSettingsFile = "nlash-general-settings.json"

type hostOverride struct {
	Host  string `json:"host"`
	Value string `json:"value"`
}

type generalSettings struct {
	MixedPort            int            `json:"mixedPort"`
	AllowLan             bool           `json:"allowLan"`
	ExternalController   bool           `json:"externalController"`
	ControllerSecret     string         `json:"controllerSecret"`
	Authentication       bool           `json:"authentication"`
	Username             string         `json:"username"`
	Password             string         `json:"password"`
	UnifiedDelay         bool           `json:"unifiedDelay"`
	TCPConcurrent        bool           `json:"tcpConcurrent"`
	FindProcess          bool           `json:"findProcess"`
	AutoCloseConnections bool           `json:"autoCloseConnections"`
	OnlyProxyTraffic     bool           `json:"onlyProxyTraffic"`
	IPv6                 bool           `json:"ipv6"`
	Hosts                []hostOverride `json:"hosts"`
	AppendSystemDNS      bool           `json:"appendSystemDns"`
	GeoMemoryMode        bool           `json:"geoMemoryMode"`
}

func defaultGeneralSettings() generalSettings {
	return generalSettings{MixedPort: 7890, UnifiedDelay: true, TCPConcurrent: true,
		AutoCloseConnections: true, GeoMemoryMode: true, Hosts: []hostOverride{}}
}

func validateGeneralSettings(settings generalSettings) error {
	if settings.MixedPort < 0 || settings.MixedPort > 65535 ||
		(settings.ExternalController && settings.MixedPort == 9090) {
		return errors.New("端口须为 0–65535，且不能与控制器端口 9090 冲突")
	}
	for _, value := range []string{settings.Username, settings.Password, settings.ControllerSecret} {
		if len(value) > 128 || strings.ContainsFunc(value, unicode.IsControl) {
			return errors.New("账号、密码和密钥最多 128 字节，不能包含控制字符")
		}
	}
	if strings.Contains(settings.Username, ":") {
		return errors.New("认证账号不能包含冒号")
	}
	if settings.Authentication && (strings.TrimSpace(settings.Username) == "" || strings.TrimSpace(settings.Password) == "") {
		return errors.New("开启认证时须填写账号和密码")
	}
	if settings.ExternalController && strings.TrimSpace(settings.ControllerSecret) == "" {
		return errors.New("开启外部控制器时须填写密钥")
	}
	if len(settings.Hosts) > 64 {
		return errors.New("Hosts 最多支持 64 条")
	}
	seen := make(map[string]bool)
	for _, entry := range settings.Hosts {
		host := strings.ToLower(entry.Host)
		_, domainError := trie.ValidAndSplitDomain(host)
		if domainError != nil || len(host) > 253 || strings.ContainsAny(host, " \t\r\n/:=\x00") || seen[host] {
			return errors.New("Hosts 域名无效或重复")
		}
		seen[host] = true
		values := strings.FieldsFunc(entry.Value, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' })
		if len(values) == 0 || len(values) > 16 || len(entry.Value) > 1024 || strings.ContainsAny(entry.Value, "\r\n\x00") {
			return errors.New("Hosts 值须为 IP 地址或域名，多个 IP 用逗号分隔")
		}
		for _, value := range values {
			if len(values) == 1 && value == "lan" {
				continue
			}
			_, domainError := trie.ValidAndSplitDomain(value)
			if _, err := netip.ParseAddr(value); err != nil &&
				(len(values) != 1 || domainError != nil || len(value) > 253 || strings.ContainsAny(value, ":/=*") || !strings.Contains(value, ".")) {
				return errors.New("Hosts 值须为 IP 地址或域名，多个 IP 用逗号分隔")
			}
		}
	}
	return nil
}

func readGeneralSettings(home string) (generalSettings, error) {
	settings := defaultGeneralSettings()
	data, err := os.ReadFile(filepath.Join(home, generalSettingsFile))
	if os.IsNotExist(err) {
		return settings, nil
	}
	if err != nil {
		return settings, err
	}
	if len(data) > maxCoreCommandBytes {
		return settings, errors.New("常规设置文件过大")
	}
	if err = json.Unmarshal(data, &settings); err != nil {
		return settings, errors.New("常规设置文件无效")
	}
	if settings.Hosts == nil {
		settings.Hosts = []hostOverride{}
	}
	return settings, validateGeneralSettings(settings)
}

// 应用层只覆写自己管理的项目，订阅原文与其他 DNS、规则配置保持完整。
func applyGeneralOverrides(raw *config.RawConfig, settings generalSettings, systemDNS []string) {
	raw.MixedPort = settings.MixedPort
	raw.AllowLan = settings.AllowLan
	raw.BindAddress = "*"
	raw.Authentication = nil
	raw.SkipAuthPrefixes = nil
	if settings.Authentication {
		raw.Authentication = []string{settings.Username + ":" + settings.Password}
	}
	raw.ExternalController = ""
	raw.ExternalControllerTLS, raw.ExternalControllerUnix, raw.ExternalControllerPipe = "", "", ""
	raw.ExternalUI, raw.ExternalUIURL = "", ""
	raw.Secret = settings.ControllerSecret
	if settings.ExternalController {
		raw.ExternalController = "127.0.0.1:9090"
	}
	raw.UnifiedDelay, raw.TCPConcurrent = settings.UnifiedDelay, settings.TCPConcurrent
	raw.FindProcessMode = process.FindProcessOff
	if settings.FindProcess {
		raw.FindProcessMode = process.FindProcessAlways
	}
	raw.IPv6, raw.DNS.IPv6 = settings.IPv6, settings.IPv6
	raw.GeodataLoader = "standard"
	if settings.GeoMemoryMode {
		raw.GeodataLoader = "memconservative"
	}
	if raw.Hosts == nil {
		raw.Hosts = make(map[string]any)
	}
	for _, entry := range settings.Hosts {
		for domain := range raw.Hosts {
			if strings.EqualFold(domain, entry.Host) {
				delete(raw.Hosts, domain)
			}
		}
		values := strings.FieldsFunc(entry.Value, func(r rune) bool { return r == ',' || r == ' ' || r == '\t' })
		if len(values) == 1 {
			raw.Hosts[entry.Host] = values[0]
		} else {
			raw.Hosts[entry.Host] = values
		}
	}
	if len(settings.Hosts) > 0 {
		raw.DNS.UseHosts = true
	}
	if settings.AppendSystemDNS {
		for _, server := range systemDNS {
			if !slices.Contains(raw.DNS.NameServer, server) {
				raw.DNS.NameServer = append(raw.DNS.NameServer, server)
			}
		}
	}
}

func randomSecret(size int) (string, error) {
	data := make([]byte, size)
	if _, err := rand.Read(data); err != nil {
		return "", err
	}
	return hex.EncodeToString(data), nil
}

func (runtime *coreRuntime) saveGeneralSettings(payload json.RawMessage) coreCommandResponse {
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.workDir == "" {
		return commandFailure("CORE_NOT_RUNNING", "请先启动 Core 宿主")
	}
	next, err := readGeneralSettings(runtime.workDir)
	if err != nil {
		return commandFailure("READ_FAILED", "无法读取常规设置")
	}
	previous := next
	decoder := json.NewDecoder(bytes.NewReader(payload))
	decoder.DisallowUnknownFields()
	if len(payload) == 0 || payload[0] != '{' || decoder.Decode(&next) != nil {
		return commandFailure("INVALID_ARGUMENT", "常规设置无效")
	}
	// 首次开启生成独立随机凭据；后续编辑仍执行非空校验。
	if next.Authentication && !previous.Authentication && next.Username == "" && next.Password == "" {
		var err error
		next.Username, err = randomSecret(4)
		if err == nil {
			next.Password, err = randomSecret(16)
		}
		if err != nil {
			return commandFailure("INTERNAL_ERROR", "生成认证信息失败")
		}
	}
	if next.ExternalController && !previous.ExternalController && next.ControllerSecret == "" {
		secret, err := randomSecret(24)
		if err != nil {
			return commandFailure("INTERNAL_ERROR", "生成控制器密钥失败")
		}
		next.ControllerSecret = secret
	}
	if err := validateGeneralSettings(next); err != nil {
		return commandFailure("INVALID_ARGUMENT", err.Error())
	}
	if next.Hosts == nil {
		next.Hosts = []hostOverride{}
	}
	if runtime.state != coreRunning {
		data, err := json.Marshal(next)
		if err == nil {
			err = writeAtomic(filepath.Join(runtime.workDir, generalSettingsFile), data)
		}
		if err != nil {
			return commandFailure("SAVE_FAILED", "保存失败，原设置已保留")
		}
		runtime.general = next
		return commandSuccess(next)
	}
	if runtime.proxyEnabled && runtime.general.IPv6 != next.IPv6 {
		return commandFailure("INVALID_STATE", "更改 IPv6 前须由宿主重建 VPN")
	}
	return runtime.applyGeneralSettings(next, true)
}

// 在同一生命周期锁内应用并落盘，任何一步失败都恢复之前的运行配置和节点选择。
func (runtime *coreRuntime) applyGeneralSettings(next generalSettings, persist bool) coreCommandResponse {
	C.SetHomeDir(runtime.workDir)
	C.SetConfig(runtime.configPath)
	previous, err := runtime.parseActiveConfig(runtime.proxyEnabled)
	if err != nil {
		return commandFailure("CONFIG_INVALID", "无法读取当前配置")
	}
	cfg, _, err := parseRuntimeConfigWithSettings(runtime.configData, runtime.proxyEnabled, next, runtime.systemDNS)
	if err != nil {
		return commandFailure("CONFIG_INVALID", "常规设置与当前配置不兼容，请检查 Hosts 和 DNS")
	}
	configureReloadTun(previous, runtime.proxyEnabled)
	configureReloadTun(cfg, runtime.proxyEnabled)
	snapshot := runtime.proxySnapshot()
	err = applyRuntimeConfig(cfg)
	if err == nil {
		err = restoreProxySnapshot(snapshot)
	}
	if err == nil && persist {
		var data []byte
		data, err = json.Marshal(next)
		if err == nil {
			err = writeAtomic(filepath.Join(runtime.workDir, generalSettingsFile), data)
		}
	}
	if err != nil {
		if restoreErr := applyRuntimeConfig(previous); restoreErr != nil {
			runtime.setFailure(coreInternalError, errors.New("常规设置应用失败，原配置恢复失败"))
			emitCoreEvent(coreEventUnexpectedExit, coreFailed, coreInternalError, runtime.lastError)
			return commandFailure("ROLLBACK_FAILED", runtime.lastError)
		}
		if restoreErr := restoreProxySnapshot(snapshot); restoreErr != nil {
			return commandFailure("ROLLBACK_FAILED", "设置未保存，节点选择恢复失败")
		}
		return commandFailure("APPLY_FAILED", "应用或保存失败，已恢复原设置；请检查端口占用和存储空间")
	}
	runtime.general = next
	return commandSuccess(next)
}

func (runtime *coreRuntime) updateSystemDNS(payload json.RawMessage) coreCommandResponse {
	var servers []string
	if !decodeCommandPayload(payload, &servers) || len(servers) > 16 {
		return commandFailure("INVALID_ARGUMENT", "系统 DNS 地址无效")
	}
	for _, server := range servers {
		ip, err := netip.ParseAddr(server)
		if err != nil || ip.IsUnspecified() || ip.IsLoopback() {
			return commandFailure("INVALID_ARGUMENT", "系统 DNS 地址无效")
		}
	}
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if slices.Equal(runtime.systemDNS, servers) {
		return commandSuccess(nil)
	}
	previous := runtime.systemDNS
	runtime.systemDNS = servers
	if runtime.state == coreRunning && runtime.general.AppendSystemDNS {
		result := runtime.applyGeneralSettings(runtime.general, false)
		if !result.OK {
			runtime.systemDNS = previous
			if runtime.state == coreRunning {
				if restored := runtime.applyGeneralSettings(runtime.general, false); !restored.OK {
					return restored
				}
			}
		}
		return result
	}
	return commandSuccess(nil)
}

var controllerAddress, controllerSecret string

// 固定内核分支由宿主管理监听器；检查真实监听结果，端口占用不能显示为保存成功。
func applyHarmonyListeners(cfg *config.Config) error {
	inbound.SetSkipAuthPrefixes(cfg.General.SkipAuthPrefixes)
	inbound.SetAllowedIPs(cfg.General.LanAllowedIPs)
	inbound.SetDisAllowedIPs(cfg.General.LanDisAllowedIPs)
	listener.SetAllowLan(cfg.General.AllowLan)
	listener.SetBindAddress(cfg.General.BindAddress)
	listener.ReCreateMixed(cfg.General.MixedPort, tunnel.Tunnel)
	if listener.GetPorts().MixedPort != cfg.General.MixedPort {
		return errors.New("mixed proxy port is unavailable")
	}
	if cfg.General.MixedPort > 0 {
		// UDP 绑定失败时上游会关闭 TCP，但仍保留监听器对象，端口快照不足以证明成功。
		conn, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", strconv.Itoa(cfg.General.MixedPort)), time.Second)
		if err != nil {
			return errors.New("mixed proxy listener is unavailable")
		}
		conn.Close()
	}
	return applyController(cfg.Controller.ExternalController, cfg.Controller.Secret)
}

func applyController(address, secret string) error {
	if controllerAddress == address && controllerSecret == secret {
		return nil
	}
	subscription := coreLog.Subscribe()
	defer coreLog.UnSubscribe(subscription)
	previousAddress := controllerAddress
	controllerAddress, controllerSecret = "", ""
	route.SetEmbedMode(true)
	route.ReCreateServer(&route.Config{Addr: address, Secret: secret})
	timeout := time.NewTimer(3 * time.Second)
	defer timeout.Stop()
	ticker := time.NewTicker(20 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case event := <-subscription:
			if strings.HasPrefix(event.Payload, "External controller listen error:") {
				return errors.New("external controller port is unavailable")
			}
			if address != "" && strings.HasPrefix(event.Payload, "RESTful API listening at:") {
				controllerAddress, controllerSecret = address, secret
				return nil
			}
		case <-ticker.C:
			if address == "" {
				conn, err := net.DialTimeout("tcp", previousAddress, 50*time.Millisecond)
				if err != nil {
					controllerAddress, controllerSecret = "", secret
					return nil
				}
				conn.Close()
			}
		case <-timeout.C:
			return errors.New("external controller did not become ready")
		}
	}
}
