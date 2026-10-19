package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/resource"
	"github.com/metacubex/mihomo/config"
	C "github.com/metacubex/mihomo/constant"
	"github.com/oschwald/maxminddb-golang"
)

const geoSettingsFile = "nlash-geo-settings.json"
const maxGeoBytes = 64 * 1024 * 1024

type geoSettings struct {
	URLs          map[string]string `json:"urls,omitempty"`
	AutoUpdate    *bool             `json:"autoUpdate,omitempty"`
	IntervalHours *int              `json:"intervalHours,omitempty"`
}

type geoResource struct {
	Kind      string `json:"kind"`
	URL       string `json:"url"`
	Size      int64  `json:"size"`
	UpdatedAt int64  `json:"updatedAt"`
	Path      string `json:"-"`
}

type geoResourceSnapshot struct {
	Resources     []geoResource `json:"resources"`
	AutoUpdate    bool          `json:"autoUpdate"`
	IntervalHours int           `json:"intervalHours"`
	Updating      bool          `json:"updating"`
}

func validateGeoSettings(settings geoSettings) error {
	if settings.IntervalHours != nil && (*settings.IntervalHours < 1 || *settings.IntervalHours > 720) {
		return errors.New("自动更新间隔必须为 1–720 小时")
	}
	for kind, address := range settings.URLs {
		if kind != "MMDB" && kind != "ASN" && kind != "GEOIP" && kind != "GEOSITE" {
			return errors.New("未知资源类型")
		}
		parsed, err := url.Parse(address)
		if err != nil || len(address) > 2048 || parsed.Hostname() == "" || parsed.User != nil ||
			parsed.Fragment != "" || (parsed.Scheme != "https" && parsed.Scheme != "http") {
			return errors.New("下载源须为有效的 HTTP(S) 地址，且不能包含账号或片段")
		}
	}
	return nil
}

func readGeoSettings(home string) (geoSettings, error) {
	settings := geoSettings{URLs: map[string]string{}}
	data, err := os.ReadFile(filepath.Join(home, geoSettingsFile))
	if os.IsNotExist(err) {
		return settings, nil
	}
	if err != nil {
		return settings, err
	}
	if len(data) > maxCoreCommandBytes {
		return settings, errors.New("资源设置文件过大")
	}
	if err = json.Unmarshal(data, &settings); err != nil {
		return settings, err
	}
	if settings.URLs == nil {
		settings.URLs = map[string]string{}
	}
	return settings, validateGeoSettings(settings)
}

func applySavedGeoSettings(raw *config.RawConfig, home string) error {
	settings, err := readGeoSettings(home)
	if err != nil {
		return err
	}
	if value, ok := settings.URLs["MMDB"]; ok {
		raw.GeoXUrl.Mmdb = value
	}
	if value, ok := settings.URLs["ASN"]; ok {
		raw.GeoXUrl.ASN = value
	}
	if value, ok := settings.URLs["GEOIP"]; ok {
		raw.GeoXUrl.GeoIp = value
	}
	if value, ok := settings.URLs["GEOSITE"]; ok {
		raw.GeoXUrl.GeoSite = value
	}
	if settings.AutoUpdate != nil {
		raw.GeoAutoUpdate = *settings.AutoUpdate
	}
	if settings.IntervalHours != nil {
		raw.GeoUpdateInterval = *settings.IntervalHours
	}
	return nil
}

// 调用方持有生命周期锁，路径和配置在同一代 Core 中取得。
func (runtime *coreRuntime) resourceSnapshot() (geoResourceSnapshot, error) {
	raw, err := config.UnmarshalRawConfig(runtime.configData)
	if err != nil {
		return geoResourceSnapshot{}, err
	}
	applyHarmonyGeoMirrors(raw)
	if err = applySavedGeoSettings(raw, runtime.workDir); err != nil {
		return geoResourceSnapshot{}, err
	}
	resources := []geoResource{
		{Kind: "MMDB", URL: raw.GeoXUrl.Mmdb, Path: C.Path.MMDB()},
		{Kind: "ASN", URL: raw.GeoXUrl.ASN, Path: C.Path.ASN()},
		{Kind: "GEOIP", URL: raw.GeoXUrl.GeoIp, Path: C.Path.GeoIP()},
		{Kind: "GEOSITE", URL: raw.GeoXUrl.GeoSite, Path: C.Path.GeoSite()},
	}
	for i := range resources {
		if info, err := os.Stat(resources[i].Path); err == nil {
			resources[i].Size, resources[i].UpdatedAt = info.Size(), info.ModTime().UnixMilli()
		} else if !os.IsNotExist(err) {
			return geoResourceSnapshot{}, err
		}
	}
	return geoResourceSnapshot{Resources: resources, AutoUpdate: raw.GeoAutoUpdate,
		IntervalHours: min(720, max(1, raw.GeoUpdateInterval)), Updating: runtime.geoUpdating.Load()}, nil
}

func writeAtomic(path string, data []byte) error {
	file, err := os.CreateTemp(filepath.Dir(path), ".nlash-geo-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err = file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err = file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}

func (runtime *coreRuntime) saveGeoSettings(payload json.RawMessage) coreCommandResponse {
	var patch geoSettings
	if !decodeCommandPayload(payload, &patch) {
		return commandFailure("INVALID_ARGUMENT", "资源设置无效")
	}
	if err := validateGeoSettings(patch); err != nil {
		return commandFailure("INVALID_ARGUMENT", err.Error())
	}
	runtime.mu.Lock()
	defer runtime.mu.Unlock()
	if runtime.state != coreRunning {
		return commandFailure("CORE_NOT_RUNNING", "请先启动 Core")
	}
	if runtime.geoUpdating.Load() {
		return commandFailure("BUSY", "资源正在更新，请稍后再修改")
	}
	settings, err := readGeoSettings(runtime.workDir)
	if err != nil {
		return commandFailure("READ_FAILED", "无法读取资源设置")
	}
	for kind, address := range patch.URLs {
		settings.URLs[kind] = address
	}
	if patch.AutoUpdate != nil {
		settings.AutoUpdate = patch.AutoUpdate
	}
	if patch.IntervalHours != nil {
		settings.IntervalHours = patch.IntervalHours
	}
	data, err := json.Marshal(settings)
	if err == nil {
		err = writeAtomic(filepath.Join(runtime.workDir, geoSettingsFile), data)
	}
	if err != nil {
		return commandFailure("SAVE_FAILED", "保存失败，原资源设置已保留")
	}
	runtime.scheduleGeoUpdates()
	snapshot, err := runtime.resourceSnapshot()
	if err != nil {
		return commandFailure("READ_FAILED", "读取资源状态失败")
	}
	return commandSuccess(snapshot)
}

func validateGeoData(kind string, data []byte) error {
	if len(data) == 0 || len(data) > maxGeoBytes {
		return errors.New("资源为空或超过 64 MiB")
	}
	if kind == "MMDB" || kind == "ASN" {
		db, err := maxminddb.FromBytes(data)
		if err != nil {
			return err
		}
		return db.Close()
	}
	loader, err := geodata.GetGeoDataLoader("standard")
	if err != nil {
		return err
	}
	switch kind {
	case "GEOIP":
		_, err = loader.LoadIPByBytes(data, "cn")
	case "GEOSITE":
		_, err = loader.LoadSiteByBytes(data, "cn")
	default:
		err = errors.New("未知资源类型")
	}
	return err
}

// 网络等待不占用生命周期锁；只在校验通过且 Core 代次仍有效时原子替换文件。
func (runtime *coreRuntime) updateGeoResources(expectedGeneration uint64) coreCommandResponse {
	if !runtime.geoUpdating.CompareAndSwap(false, true) {
		return commandFailure("BUSY", "资源正在更新")
	}
	defer runtime.geoUpdating.Store(false)
	runtime.mu.RLock()
	if runtime.state != coreRunning || (expectedGeneration != 0 && expectedGeneration != runtime.geoGeneration) {
		runtime.mu.RUnlock()
		return commandFailure("CORE_NOT_RUNNING", "请先启动 Core")
	}
	snapshot, err := runtime.resourceSnapshot()
	generation := runtime.geoGeneration
	parent := runtime.geoContext
	runtime.mu.RUnlock()
	if err != nil {
		return commandFailure("READ_FAILED", "读取资源设置失败")
	}
	if parent == nil {
		parent = context.Background()
	}
	ctx, cancel := context.WithTimeout(parent, 90*time.Second)
	defer cancel()
	failures := []string{}
	for _, item := range snapshot.Resources {
		vehicle := resource.NewHTTPVehicle(item.URL, item.Path, "", nil, 30*time.Second, maxGeoBytes+1)
		data, _, downloadErr := vehicle.Read(ctx, utils.HashType{})
		if downloadErr == nil {
			downloadErr = validateGeoData(item.Kind, data)
		}
		if downloadErr == nil {
			runtime.mu.Lock()
			if runtime.state != coreRunning || runtime.geoGeneration != generation {
				downloadErr = errors.New("Core 已切换")
			} else {
				downloadErr = writeAtomic(item.Path, data)
			}
			runtime.mu.Unlock()
		}
		if downloadErr != nil {
			failures = append(failures, item.Kind)
		}
		if ctx.Err() != nil {
			break
		}
	}
	if ctx.Err() != nil {
		return commandFailure("CANCELLED", "更新超时或 Core 已停止；未完成的资源保留原文件")
	}
	if len(failures) > 0 {
		return commandFailure("UPDATE_FAILED", fmt.Sprintf("%s 更新失败，请检查下载源后重试；原文件已保留", strings.Join(failures, "、")))
	}
	// shortcut: 已加载的数据库保持当前映射，下次启动 Core 使用新文件，避免中断现有连接。
	return commandSuccess(nil)
}

// 更新周期跟随 Core 生命周期；关闭或切换配置会取消在途下载。
func (runtime *coreRuntime) scheduleGeoUpdates() {
	if runtime.geoCancel != nil {
		runtime.geoCancel()
	}
	if runtime.geoTimer != nil {
		runtime.geoTimer.Stop()
		runtime.geoTimer = nil
	}
	runtime.geoGeneration++
	runtime.geoContext, runtime.geoCancel = context.WithCancel(context.Background())
	if runtime.state != coreRunning {
		return
	}
	snapshot, err := runtime.resourceSnapshot()
	if err != nil || !snapshot.AutoUpdate {
		return
	}
	generation := runtime.geoGeneration
	runtime.geoTimer = time.AfterFunc(time.Duration(snapshot.IntervalHours)*time.Hour, func() {
		runtime.updateGeoResources(generation)
		runtime.mu.Lock()
		defer runtime.mu.Unlock()
		if runtime.state == coreRunning && runtime.geoGeneration == generation {
			runtime.scheduleGeoUpdates()
		}
	})
}
