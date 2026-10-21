import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { resourceManager } from '@kit.LocalizationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemeControl } from '@kit.ArkUI';
import { AppSettings, AppThemeMode, NavigationTransition, SettingsStoreListener, SettingsStoreSnapshot } from '../model/SettingsModels';
import { DEFAULT_APP_SETTINGS } from '../constants/SettingsConstants';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { normalizeAppSettings } from '../utils/SettingsUtils';
import { resolveAppTheme } from '../utils/ThemeUtils';

/** 维护应用设置快照，并在持久化成功后通知页面、应用系统主题。 */
class SettingsStore {
  private context: common.ApplicationContext | undefined;
  private settings: AppSettings = DEFAULT_APP_SETTINGS;
  private saving: boolean = false;
  private initialized: boolean = false;
  private initializeOperation: Promise<void> | undefined;
  private windowReady: boolean = false;
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
    const next = this.copySettings(this.settings);
    next.themeMode = mode;
    await this.setAppearance(next);
  }

  async setNavigationTransition(transition: NavigationTransition): Promise<void> {
    const next = this.copySettings(this.settings);
    next.navigationTransition = transition;
    await this.setAppearance(next);
  }

  async setAppearance(settings: AppSettings): Promise<void> {
    const next = this.copySettings(settings);
    next.mtu = this.settings.mtu;
    next.delayTestUrl = this.settings.delayTestUrl;
    const previousMode = this.settings.themeMode;
    await this.save(next);
    if (previousMode !== next.themeMode) { this.applyTheme(next.themeMode); }
    this.refreshTheme();
  }

  /** 系统配色变化和自定义外观均替换同一对象，已挂载的页面与弹窗即时刷新。 */
  refreshTheme(): void {
    const resources = this.context?.resourceManager;
    let dark = false;
    let systemAccent = DEFAULT_APP_SETTINGS.themeColor;
    try {
      dark = resources?.getConfigurationSync().colorMode === resourceManager.ColorMode.DARK;
      if (resources !== undefined) {
        const color = resources.getColorSync($r('sys.color.ohos_id_color_emphasize').id);
        systemAccent = '#' + (color & 0xFFFFFF).toString(16).padStart(6, '0');
      }
    } catch (error) {
      hilog.warn(0x0000, 'NlashTheme', 'Cannot read system palette: %{public}s', String(error));
    }
    const theme = resolveAppTheme(this.settings, dark, systemAccent);
    AppStorage.setOrCreate('appTheme', theme);
    ThemeControl.setDefaultTheme({ colors: {
      brand: theme.accent,
      fontEmphasize: theme.accent,
      iconEmphasize: theme.accent,
      backgroundPrimary: theme.background,
      backgroundSecondary: theme.surface,
      compBackgroundPrimary: theme.surface,
      compBackgroundEmphasize: theme.accent,
      compEmphasizeSecondary: theme.accentSurface
    } });
  }

  onWindowReady(): void {
    this.windowReady = true;
    this.applyTheme(this.settings.themeMode);
    this.refreshTheme();
  }

  async setMtu(mtu: number): Promise<void> {
    if (!Number.isFinite(mtu) || mtu < 1280 || mtu > 9000) {
      throw new Error('MTU 必须在 1280–9000 之间');
    }
    const next = this.copySettings(this.settings);
    next.mtu = Math.round(mtu);
    await this.save(next);
  }

  async setDelayTestUrl(url: string): Promise<void> {
    const value = url.trim();
    if ((!value.startsWith('https://') && !value.startsWith('http://')) || value.length > 2048) {
      throw new Error('延迟测试地址必须是有效的 HTTP(S) URL');
    }
    const next = this.copySettings(this.settings);
    next.delayTestUrl = value;
    await this.save(next);
  }

  /** 同时校验并保存网络设置，避免表单的一部分成功、另一部分失败。 */
  async setNetworkSettings(mtu: number, url: string): Promise<void> {
    if (!Number.isFinite(mtu) || mtu < 1280 || mtu > 9000) {
      throw new Error('MTU 必须在 1280–9000 之间');
    }
    const value = url.trim();
    if ((!value.startsWith('https://') && !value.startsWith('http://')) || value.length > 2048) {
      throw new Error('延迟测试地址必须是有效的 HTTP(S) URL');
    }
    const next = this.copySettings(this.settings);
    next.mtu = Math.round(mtu);
    next.delayTestUrl = value;
    await this.save(next);
  }

  private async initializeInternal(context: common.ApplicationContext): Promise<void> {
    await preferenceRepository.initialize(context);
    this.settings = await preferenceRepository.getAppSettings();
    this.initialized = true;
    this.applyTheme(this.settings.themeMode);
    this.refreshTheme();
    this.publish();
  }

  // 先落盘再替换内存设置，失败时仍向订阅者保留最后一次成功保存的值。
  private async save(settings: AppSettings): Promise<void> {
    if (this.initializeOperation !== undefined) {
      await this.initializeOperation;
    }
    if (!this.initialized) {
      throw new Error('设置尚未初始化');
    }
    if (this.saving) { throw new Error('设置正在保存，请稍后重试'); }
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
    if (context === undefined || !this.windowReady) {
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
    return normalizeAppSettings(settings);
  }

  private publish(): void {
    const snapshot = this.getSnapshot();
    this.listeners.forEach((listener: SettingsStoreListener): void => {
      listener(snapshot);
    });
  }
}

export const settingsStore = new SettingsStore();
