import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ProxySelection, RuntimeMode } from '../model/RuntimeModels';
import { AppSettings, AppThemeMode } from '../model/SettingsModels';
import { DEFAULT_APP_SETTINGS } from '../constants/SettingsConstants';
import { isRefreshIntervalSeconds } from '../utils/SettingsUtils';

const PREFERENCES_NAME = 'nlash_settings';
const ACTIVE_PROFILE_ID = 'activeProfileId';
const ACTIVE_PROFILE_PATH = 'activeProfilePath';
const THEME_MODE = 'themeMode';
const VPN_MTU = 'vpnMtu';
const DELAY_TEST_URL = 'delayTestUrl';
const REFRESH_INTERVAL_SECONDS = 'refreshIntervalSeconds';
const NOTIFICATION_PERMISSION_REQUESTED = 'notificationPermissionRequested';
const PROXY_SELECTIONS = 'proxySelections';
const PROXY_GROUPS = 'proxyGroups';
const MAX_PROXY_SELECTIONS = 768;
const MAX_PROXY_GROUPS = 128;

export interface StoredProxySelection {
  profileId: string;
  mode?: RuntimeMode;
  group: string;
  proxy: string;
}

export interface StoredProxyGroup {
  profileId: string;
  mode: RuntimeMode;
  group: string;
}

function isRuntimeMode(value: Object | undefined): boolean {
  return value === RuntimeMode.RULE || value === RuntimeMode.GLOBAL || value === RuntimeMode.DIRECT;
}

export function parseStoredProxySelections(value: string): StoredProxySelection[] {
  let records: StoredProxySelection[];
  try {
    records = JSON.parse(value) as StoredProxySelection[];
  } catch (error) {
    return [];
  }
  if (!Array.isArray(records)) {
    return [];
  }
  return records.filter((record: StoredProxySelection): boolean => record !== undefined &&
    typeof record.profileId === 'string' && record.profileId.length > 0 &&
    (record.mode === undefined || isRuntimeMode(record.mode)) &&
    typeof record.group === 'string' && record.group.length > 0 &&
    typeof record.proxy === 'string' && record.proxy.length > 0);
}

export function selectStoredProfile(records: StoredProxySelection[], profileId: string,
  mode: RuntimeMode = RuntimeMode.RULE): ProxySelection[] {
  const selected = new Map<string, string>();
  records.filter((record: StoredProxySelection): boolean =>
    record.profileId === profileId && record.mode === mode)
    .forEach((record: StoredProxySelection): void => {
      selected.set(record.group, record.proxy);
    });
  if (mode === RuntimeMode.RULE) {
    records.filter((record: StoredProxySelection): boolean =>
      record.profileId === profileId && record.mode === undefined)
      .forEach((record: StoredProxySelection): void => {
        if (!selected.has(record.group)) {
          selected.set(record.group, record.proxy);
        }
      });
  }
  const result: ProxySelection[] = [];
  selected.forEach((proxy: string, group: string): void => {
    result.push({ group: group, proxy: proxy });
  });
  return result;
}

export function parseStoredProxyGroups(value: string): StoredProxyGroup[] {
  let records: StoredProxyGroup[];
  try {
    records = JSON.parse(value) as StoredProxyGroup[];
  } catch (error) {
    return [];
  }
  if (!Array.isArray(records)) {
    return [];
  }
  return records.filter((record: StoredProxyGroup): boolean => record !== undefined &&
    typeof record.profileId === 'string' && record.profileId.length > 0 && isRuntimeMode(record.mode) &&
    typeof record.group === 'string' && record.group.length > 0);
}

export function selectStoredProxyGroup(records: StoredProxyGroup[], profileId: string,
  mode: RuntimeMode): string {
  return records.find((record: StoredProxyGroup): boolean =>
    record.profileId === profileId && record.mode === mode)?.group ?? '';
}

class PreferenceRepository {
  private store: preferences.Preferences | undefined;
  private initializeOperation: Promise<void> | undefined;

  initialize(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return Promise.resolve();
    }
    if (this.initializeOperation === undefined) {
      const operation = this.initializeInternal(context);
      this.initializeOperation = operation;
      operation.then((): void => {
        this.initializeOperation = undefined;
      }, (): void => {
        this.initializeOperation = undefined;
      });
    }
    return this.initializeOperation;
  }

  async getActiveProfileId(): Promise<string> {
    const value = await this.requireStore().get(ACTIVE_PROFILE_ID, '');
    return typeof value === 'string' ? value : '';
  }

  async getActiveProfilePath(): Promise<string> {
    const value = await this.requireStore().get(ACTIVE_PROFILE_PATH, '');
    return typeof value === 'string' ? value : '';
  }

  async setActiveProfile(id: string, path: string): Promise<void> {
    const store = this.requireStore();
    await store.put(ACTIVE_PROFILE_ID, id);
    await store.put(ACTIVE_PROFILE_PATH, path);
    await store.flush();
  }

  async clearActiveProfile(): Promise<void> {
    await this.setActiveProfile('', '');
  }

  async getAppSettings(): Promise<AppSettings> {
    const store = this.requireStore();
    const themeValue = await store.get(THEME_MODE, DEFAULT_APP_SETTINGS.themeMode);
    const mtuValue = await store.get(VPN_MTU, DEFAULT_APP_SETTINGS.mtu);
    const testUrlValue = await store.get(DELAY_TEST_URL, DEFAULT_APP_SETTINGS.delayTestUrl);
    const refreshIntervalValue = await store.get(REFRESH_INTERVAL_SECONDS,
      DEFAULT_APP_SETTINGS.refreshIntervalSeconds);
    return {
      themeMode: this.parseThemeMode(typeof themeValue === 'string' ? themeValue : ''),
      mtu: typeof mtuValue === 'number' && mtuValue >= 1280 && mtuValue <= 9000 ?
        Math.round(mtuValue) : DEFAULT_APP_SETTINGS.mtu,
      delayTestUrl: typeof testUrlValue === 'string' && this.isHttpUrl(testUrlValue) ?
        testUrlValue : DEFAULT_APP_SETTINGS.delayTestUrl,
      refreshIntervalSeconds: typeof refreshIntervalValue === 'number' &&
        isRefreshIntervalSeconds(refreshIntervalValue) ? refreshIntervalValue :
        DEFAULT_APP_SETTINGS.refreshIntervalSeconds
    };
  }

  async saveAppSettings(settings: AppSettings): Promise<void> {
    const store = this.requireStore();
    await store.put(THEME_MODE, settings.themeMode);
    await store.put(VPN_MTU, settings.mtu);
    await store.put(DELAY_TEST_URL, settings.delayTestUrl);
    await store.put(REFRESH_INTERVAL_SECONDS, settings.refreshIntervalSeconds);
    await store.flush();
  }

  async getNotificationPermissionRequested(): Promise<boolean> {
    const value = await this.requireStore().get(NOTIFICATION_PERMISSION_REQUESTED, false);
    return typeof value === 'boolean' && value;
  }

  async setNotificationPermissionRequested(): Promise<void> {
    const store = this.requireStore();
    await store.put(NOTIFICATION_PERMISSION_REQUESTED, true);
    await store.flush();
  }

  async getProxySelections(profileId: string, mode: RuntimeMode): Promise<ProxySelection[]> {
    const records = await this.readProxySelectionRecords();
    return selectStoredProfile(records, profileId, mode);
  }

  async setProxySelection(profileId: string, mode: RuntimeMode, group: string, proxy: string): Promise<void> {
    const current = await this.getProxySelections(profileId, mode);
    const replaced: ProxySelection[] = [];
    let updated = false;
    current.forEach((selection: ProxySelection): void => {
      if (selection.group === group) {
        if (!updated) {
          replaced.push({ group: group, proxy: proxy });
          updated = true;
        }
      } else {
        replaced.push({ group: selection.group, proxy: selection.proxy });
      }
    });
    if (!updated) {
      replaced.push({ group: group, proxy: proxy });
    }
    await this.replaceProxySelections(profileId, mode, replaced);
  }

  async replaceProxySelections(profileId: string, mode: RuntimeMode, selections: ProxySelection[]): Promise<void> {
    const records = (await this.readProxySelectionRecords()).filter((record: StoredProxySelection): boolean =>
      record.profileId !== profileId || (record.mode !== mode &&
        !(mode === RuntimeMode.RULE && record.mode === undefined)));
    selections.slice(0, MAX_PROXY_SELECTIONS).forEach((selection: ProxySelection): void => {
      if (this.isSelectionValue(profileId) && this.isSelectionValue(selection.group) &&
        this.isSelectionValue(selection.proxy)) {
        records.push({
          profileId: profileId,
          mode: mode,
          group: selection.group,
          proxy: selection.proxy
        });
      }
    });
    const store = this.requireStore();
    await store.put(PROXY_SELECTIONS, JSON.stringify(records.slice(-MAX_PROXY_SELECTIONS)));
    await store.flush();
  }

  async removeProxySelections(profileId: string): Promise<void> {
    const records = (await this.readProxySelectionRecords()).filter(
      (record: StoredProxySelection): boolean => record.profileId !== profileId);
    const store = this.requireStore();
    await store.put(PROXY_SELECTIONS, JSON.stringify(records.slice(-MAX_PROXY_SELECTIONS)));
    await store.flush();
  }

  async getProxyGroup(profileId: string, mode: RuntimeMode): Promise<string> {
    return selectStoredProxyGroup(await this.readProxyGroupRecords(), profileId, mode);
  }

  async setProxyGroup(profileId: string, mode: RuntimeMode, group: string): Promise<void> {
    const records = (await this.readProxyGroupRecords()).filter((record: StoredProxyGroup): boolean =>
      record.profileId !== profileId || record.mode !== mode);
    if (this.isSelectionValue(profileId) && this.isSelectionValue(group)) {
      records.push({ profileId: profileId, mode: mode, group: group });
    }
    const store = this.requireStore();
    await store.put(PROXY_GROUPS, JSON.stringify(records.slice(-MAX_PROXY_GROUPS)));
    await store.flush();
  }

  async removeProxyGroups(profileId: string): Promise<void> {
    const records = (await this.readProxyGroupRecords()).filter(
      (record: StoredProxyGroup): boolean => record.profileId !== profileId);
    const store = this.requireStore();
    await store.put(PROXY_GROUPS, JSON.stringify(records.slice(-MAX_PROXY_GROUPS)));
    await store.flush();
  }

  async removeProxyState(profileId: string): Promise<void> {
    await this.removeProxySelections(profileId);
    await this.removeProxyGroups(profileId);
  }

  private async initializeInternal(context: common.Context): Promise<void> {
    this.store = await preferences.getPreferences(context, { name: PREFERENCES_NAME });
  }

  private requireStore(): preferences.Preferences {
    if (this.store === undefined) {
      throw new Error('Preferences 尚未初始化');
    }
    return this.store;
  }

  private parseThemeMode(value: string): AppThemeMode {
    if (value === AppThemeMode.LIGHT) {
      return AppThemeMode.LIGHT;
    }
    if (value === AppThemeMode.DARK) {
      return AppThemeMode.DARK;
    }
    return AppThemeMode.SYSTEM;
  }

  private isHttpUrl(value: string): boolean {
    return value.startsWith('https://') || value.startsWith('http://');
  }

  private async readProxySelectionRecords(): Promise<StoredProxySelection[]> {
    const value = await this.requireStore().get(PROXY_SELECTIONS, '[]');
    if (typeof value !== 'string') {
      return [];
    }
    return parseStoredProxySelections(value).filter((record: StoredProxySelection): boolean =>
      this.isSelectionValue(record.profileId) && this.isSelectionValue(record.group) &&
      this.isSelectionValue(record.proxy));
  }

  private async readProxyGroupRecords(): Promise<StoredProxyGroup[]> {
    const value = await this.requireStore().get(PROXY_GROUPS, '[]');
    if (typeof value !== 'string') {
      return [];
    }
    return parseStoredProxyGroups(value).filter((record: StoredProxyGroup): boolean =>
      this.isSelectionValue(record.profileId) && this.isSelectionValue(record.group));
  }

  private isSelectionValue(value: string): boolean {
    return typeof value === 'string' && value.length > 0 && value.length <= 256;
  }
}

export const preferenceRepository = new PreferenceRepository();
