export enum AppThemeMode {
  SYSTEM = 'SYSTEM',
  LIGHT = 'LIGHT',
  DARK = 'DARK'
}

export const REFRESH_INTERVAL_OPTIONS: number[] = [3, 5, 10, 30];

export function isRefreshIntervalSeconds(value: number): boolean {
  return REFRESH_INTERVAL_OPTIONS.includes(value);
}

export function resolveRefreshIntervalMilliseconds(value: number): number {
  const seconds = isRefreshIntervalSeconds(value) ? value : 3;
  return seconds * 1000;
}

export interface AppSettings {
  themeMode: AppThemeMode;
  mtu: number;
  delayTestUrl: string;
  refreshIntervalSeconds: number;
}

export interface SettingsStoreSnapshot {
  settings: AppSettings;
  saving: boolean;
}

export type SettingsStoreListener = (snapshot: SettingsStoreSnapshot) => void;

export const DEFAULT_APP_SETTINGS: AppSettings = {
  themeMode: AppThemeMode.SYSTEM,
  mtu: 1400,
  delayTestUrl: 'https://www.gstatic.com/generate_204',
  refreshIntervalSeconds: 3
};
