import { DEFAULT_APP_SETTINGS, NAVIGATION_TRANSITION_OPTIONS } from '../constants/SettingsConstants';
import { AppFont, AppSettings, AppThemeMode, NavigationTransition, ThemeColorStyle } from '../model/SettingsModels';
import { THEME_FONTS, THEME_COLOR_STYLES, MIN_CUSTOM_FONT_SCALE, MAX_CUSTOM_FONT_SCALE } from '../constants/ThemeConstants';
import { normalizeThemeColor } from './ThemeUtils';

/** 已保存值可能来自旧版本或异常数据，未知过渡类型回退到项目默认值。 */
export function resolveNavigationTransition(value: string): NavigationTransition {
  return NAVIGATION_TRANSITION_OPTIONS.find((transition: NavigationTransition): boolean => transition === value) ??
    DEFAULT_APP_SETTINGS.navigationTransition;
}

/** 同时供偏好迁移与保存使用，旧版本缺失字段保留默认值。 */
export function normalizeAppSettings(settings: AppSettings): AppSettings {
  return {
    themeMode: settings.themeMode === AppThemeMode.LIGHT || settings.themeMode === AppThemeMode.DARK ?
      settings.themeMode : AppThemeMode.SYSTEM,
    navigationTransition: resolveNavigationTransition(settings.navigationTransition),
    pureBlack: settings.pureBlack === true,
    themeColor: settings.themeColor === 'SYSTEM' ? 'SYSTEM' :
      normalizeThemeColor(typeof settings.themeColor === 'string' ? settings.themeColor : '') ?? DEFAULT_APP_SETTINGS.themeColor,
    customThemeColor: normalizeThemeColor(typeof settings.customThemeColor === 'string' ? settings.customThemeColor : '') ??
      DEFAULT_APP_SETTINGS.customThemeColor,
    themeColorStyle: THEME_COLOR_STYLES.includes(settings.themeColorStyle) ? settings.themeColorStyle : ThemeColorStyle.VIVID,
    fontFamily: THEME_FONTS.includes(settings.fontFamily) ? settings.fontFamily : AppFont.SYSTEM,
    followSystemFontScale: settings.followSystemFontScale !== false,
    customFontScale: Number.isFinite(settings.customFontScale) && settings.customFontScale >= MIN_CUSTOM_FONT_SCALE &&
      settings.customFontScale <= MAX_CUSTOM_FONT_SCALE ? settings.customFontScale : DEFAULT_APP_SETTINGS.customFontScale,
    mtu: settings.mtu,
    delayTestUrl: settings.delayTestUrl
  };
}

export function parseAppearanceSettings(value: string): AppSettings {
  try {
    const saved = JSON.parse(value) as AppSettings;
    if (saved !== null && typeof saved === 'object' && !Array.isArray(saved)) {
      return normalizeAppSettings(saved);
    }
  } catch (error) {
    // 损坏的外观偏好不影响既有配置与网络设置。
  }
  return normalizeAppSettings(DEFAULT_APP_SETTINGS);
}
