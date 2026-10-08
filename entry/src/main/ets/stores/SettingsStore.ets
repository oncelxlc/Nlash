import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { AppSettings, AppThemeMode, NavigationTransition, SettingsStoreListener, SettingsStoreSnapshot } from '../model/SettingsModels';
import { DEFAULT_APP_SETTINGS } from '../constants/SettingsConstants';
import { isRefreshIntervalSeconds } from '../utils/SettingsUtils';
import { preferenceRepository } from '../repository/PreferenceRepository';

class SettingsStore {
  private context: common.ApplicationContext | undefined;
  private settings: AppSettings = DEFAULT_APP_SETTINGS;
  private saving: boolean = false;
  private initialized: boolean = false;
  private initializeOperation: Promise<void> | undefined;
  private listeners: Set<SettingsStoreListener> = new Set<SettingsStoreListener>();

  initialize(context: common.ApplicationContext): Promise<void> {
    this.context = context;
    if (this.initialized) {
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

  getSnapshot(): SettingsStoreSnapshot {
    return {
      settings: this.copySettings(this.settings),
      saving: this.saving
    };
  }

  subscribe(listener: SettingsStoreListener): () => void {
    this.listeners.add(listener);
    listener(this.getSnapshot());
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  async setThemeMode(mode: AppThemeMode): Promise<void> {
    await this.save({
      themeMode: mode,
      navigationTransition: this.settings.navigationTransition,
      mtu: this.settings.mtu,
      delayTestUrl: this.settings.delayTestUrl,
      refreshIntervalSeconds: this.settings.refreshIntervalSeconds
    });
    this.applyTheme(mode);
  }

  async setNavigationTransition(transition: NavigationTransition): Promise<void> {
    await this.save({
      themeMode: this.settings.themeMode,
      navigationTransition: transition,
      mtu: this.settings.mtu,
      delayTestUrl: this.settings.delayTestUrl,
      refreshIntervalSeconds: this.settings.refreshIntervalSeconds
    });
  }

  async setMtu(mtu: number): Promise<void> {
    if (!Number.isFinite(mtu) || mtu < 1280 || mtu > 9000) {
      throw new Error('MTU 必须在 1280–9000 之间');
    }
    await this.save({
      themeMode: this.settings.themeMode,
      mtu: Math.round(mtu),
      navigationTransition: this.settings.navigationTransition,
      delayTestUrl: this.settings.delayTestUrl,
      refreshIntervalSeconds: this.settings.refreshIntervalSeconds
    });
  }

  async setDelayTestUrl(url: string): Promise<void> {
    const value = url.trim();
    if ((!value.startsWith('https://') && !value.startsWith('http://')) || value.length > 2048) {
      throw new Error('延迟测试地址必须是有效的 HTTP(S) URL');
    }
    await this.save({
      themeMode: this.settings.themeMode,
      mtu: this.settings.mtu,
      delayTestUrl: value,
      navigationTransition: this.settings.navigationTransition,
      refreshIntervalSeconds: this.settings.refreshIntervalSeconds
    });
  }

  async setNetworkSettings(mtu: number, url: string): Promise<void> {
    if (!Number.isFinite(mtu) || mtu < 1280 || mtu > 9000) {
      throw new Error('MTU 必须在 1280–9000 之间');
    }
    const value = url.trim();
    if ((!value.startsWith('https://') && !value.startsWith('http://')) || value.length > 2048) {
      throw new Error('延迟测试地址必须是有效的 HTTP(S) URL');
    }
    await this.save({
      themeMode: this.settings.themeMode,
      mtu: Math.round(mtu),
      delayTestUrl: value,
      navigationTransition: this.settings.navigationTransition,
      refreshIntervalSeconds: this.settings.refreshIntervalSeconds
    });
  }

  async setRefreshIntervalSeconds(seconds: number): Promise<void> {
    if (!isRefreshIntervalSeconds(seconds)) {
      throw new Error('刷新间隔必须是 3、5、10 或 30 秒');
    }
    await this.save({
      themeMode: this.settings.themeMode,
      mtu: this.settings.mtu,
      delayTestUrl: this.settings.delayTestUrl,
      refreshIntervalSeconds: seconds,
      navigationTransition: this.settings.navigationTransition
    });
  }

  private async initializeInternal(context: common.ApplicationContext): Promise<void> {
    await preferenceRepository.initialize(context);
    this.settings = await preferenceRepository.getAppSettings();
    this.initialized = true;
    this.applyTheme(this.settings.themeMode);
    this.publish();
  }

  private async save(settings: AppSettings): Promise<void> {
    if (this.initializeOperation !== undefined) {
      await this.initializeOperation;
    }
    if (!this.initialized) {
      throw new Error('设置尚未初始化');
    }
    this.saving = true;
    this.publish();
    try {
      await preferenceRepository.saveAppSettings(settings);
      this.settings = this.copySettings(settings);
    } catch (error) {
      throw new Error('设置保存失败');
    } finally {
      this.saving = false;
      this.publish();
    }
  }

  private applyTheme(mode: AppThemeMode): void {
    const context = this.context;
    if (context === undefined) {
      return;
    }
    let colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET;
    if (mode === AppThemeMode.LIGHT) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT;
    } else if (mode === AppThemeMode.DARK) {
      colorMode = ConfigurationConstant.ColorMode.COLOR_MODE_DARK;
    }
    try {
      context.setColorMode(colorMode);
    } catch (error) {
      throw new Error('主题切换失败');
    }
  }

  private copySettings(settings: AppSettings): AppSettings {
    return {
      themeMode: settings.themeMode,
      navigationTransition: settings.navigationTransition,
      mtu: settings.mtu,
      delayTestUrl: settings.delayTestUrl,
      refreshIntervalSeconds: settings.refreshIntervalSeconds
    };
  }

  private publish(): void {
    const snapshot = this.getSnapshot();
    this.listeners.forEach((listener: SettingsStoreListener): void => {
      listener(snapshot);
    });
  }
}

export const settingsStore = new SettingsStore();
