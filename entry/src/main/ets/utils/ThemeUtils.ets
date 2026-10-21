import { AppSettings, AppThemeMode, ThemeColorStyle } from '../model/SettingsModels';
import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_SETTINGS } from '../constants/SettingsConstants';

export function normalizeThemeColor(value: string): string | undefined {
  const color = value.trim().toUpperCase();
  return /^#[0-9A-F]{6}$/.test(color) ? color : undefined;
}

function channel(color: string, shift: number): number {
  return (parseInt(color.slice(1), 16) >>> shift) & 255;
}

export function mixThemeColor(color: string, target: string, amount: number): string {
  return '#' + [16, 8, 0].map((shift: number): string =>
    Math.round(channel(color, shift) * (1 - amount) + channel(target, shift) * amount)
      .toString(16).padStart(2, '0')).join('').toUpperCase();
}

function luminance(color: string): number {
  const channels = [16, 8, 0].map((shift: number): number => {
    const value = channel(color, shift) / 255;
    return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  });
  return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722;
}

export function themeContrast(first: string, second: string): number {
  const a = luminance(first);
  const b = luminance(second);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

function readableAccent(color: string, surface: string, dark: boolean): string {
  for (let step = 0; step <= 20; step++) {
    const candidate = mixThemeColor(color, dark ? '#FFFFFF' : '#000000', step / 20);
    if (themeContrast(candidate, dark ? '#29292D' : '#EFEDF0') >= 4.5 &&
      themeContrast(candidate, mixThemeColor(candidate, surface, dark ? 0.84 : 0.91)) >= 4.5) {
      return candidate;
    }
  }
  return dark ? '#FFFFFF' : '#000000';
}

export function resolveAppTheme(settings: AppSettings, systemDark: boolean = false,
  systemAccent: string = '#2F80FF'): AppTheme {
  const dark = settings.themeMode === AppThemeMode.DARK ||
    (settings.themeMode === AppThemeMode.SYSTEM && systemDark);
  const black = dark && settings.pureBlack;
  const background = dark ? (black ? '#000000' : '#111113') : '#F5F5F5';
  const surface = dark ? (black ? '#121214' : '#1C1C1F') : '#FFFFFF';
  let seed = settings.themeColor === 'SYSTEM' ? systemAccent : settings.themeColor;
  seed = normalizeThemeColor(seed) ?? DEFAULT_APP_SETTINGS.themeColor;
  if (settings.themeColorStyle === ThemeColorStyle.TONAL) {
    seed = mixThemeColor(seed, '#8E8E93', 0.45);
  } else if (settings.themeColorStyle === ThemeColorStyle.MONOCHROME) {
    seed = dark ? '#D4D4D8' : '#3F3F46';
  }
  const accent = readableAccent(seed, surface, dark);
  return {
    dark: dark,
    background: background,
    transparentBackground: '#00' + background.slice(1),
    surface: surface,
    inset: dark ? (black ? '#1C1C1F' : '#29292D') : '#EFEDF0',
    muted: dark ? (black ? '#29292D' : '#333338') : '#E4E4E7',
    divider: dark ? '#333338' : '#E4E4E7',
    accent: accent,
    onAccent: themeContrast(accent, '#FFFFFF') >= themeContrast(accent, '#111113') ? '#FFFFFF' : '#111113',
    accentSurface: mixThemeColor(accent, surface, dark ? 0.84 : 0.91),
    accentSecondary: mixThemeColor(accent, dark ? '#FFFFFF' : '#000000', 0.23),
    accentGlow: '#45' + accent.slice(1),
    fontFamily: settings.fontFamily,
    fontScale: settings.followSystemFontScale ? 0 : settings.customFontScale
  };
}

/** 自定义字号使用 vp，切回 fp 即恢复系统缩放，不改变应用的系统字体订阅。 */
export function themeFontSize(size: number, theme: AppTheme): number | string {
  return theme.fontScale === 0 ? size : `${Math.round(size * theme.fontScale * 100) / 100}vp`;
}

export const DEFAULT_APP_THEME: AppTheme = resolveAppTheme(DEFAULT_APP_SETTINGS);
