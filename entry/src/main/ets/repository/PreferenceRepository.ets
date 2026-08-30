import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { ProxySelection } from '../models/RuntimeModels';
import {
  AppSettings,
  AppThemeMode,
  DEFAULT_APP_SETTINGS,
  isRefreshIntervalSeconds
} from '../models/SettingsModels';

const PREFERENCES_NAME = 'nlash_settings';
const ACTIVE_PROFILE_ID = 'activeProfileId';
const ACTIVE_PROFILE_PATH = 'activeProfilePath';
const THEME_MODE = 'themeMode';
const VPN_MTU = 'vpnMtu';
const DELAY_TEST_URL = 'delayTestUrl';
const REFRESH_INTERVAL_SECONDS = 'refreshIntervalSeconds';
const PROXY_SELECTIONS = 'proxySelections';
const MAX_PROXY_SELECTIONS = 256;

export interface StoredProxySelection {
  profileId: string;
  group: string;
  proxy: string;
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
    typeof record.group === 'string' && record.group.length > 0 &&
    typeof record.proxy === 'string' && record.proxy.length > 0);
}

export function selectStoredProfile(records: StoredProxySelection[], profileId: string): ProxySelection[] {
  return records.filter((record: StoredProxySelection): boolean => record.profileId === profileId)
    .map((record: StoredProxySelection): ProxySelection => ({ group: record.group, proxy: record.proxy }));
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

  async getProxySelections(profileId: string): Promise<ProxySelection[]> {
    const records = await this.readProxySelectionRecords();
    return selectStoredProfile(records, profileId);
  }

  async setProxySelection(profileId: string, group: string, proxy: string): Promise<void> {
    const current = await this.getProxySelections(profileId);
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
    await this.replaceProxySelections(profileId, replaced);
  }

  async replaceProxySelections(profileId: string, selections: ProxySelection[]): Promise<void> {
    const records = (await this.readProxySelectionRecords()).filter(
      (record: StoredProxySelection): boolean => record.profileId !== profileId);
    selections.slice(0, MAX_PROXY_SELECTIONS).forEach((selection: ProxySelection): void => {
      if (this.isSelectionValue(profileId) && this.isSelectionValue(selection.group) &&
        this.isSelectionValue(selection.proxy)) {
        records.push({
          profileId: profileId,
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
    await this.replaceProxySelections(profileId, []);
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

  private isSelectionValue(value: string): boolean {
    return typeof value === 'string' && value.length > 0 && value.length <= 256;
  }
}

export const preferenceRepository = new PreferenceRepository();
