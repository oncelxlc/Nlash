export enum AppThemeMode {
  SYSTEM = 'SYSTEM',
  LIGHT = 'LIGHT',
  DARK = 'DARK'
}

export interface AppSettings {
  themeMode: AppThemeMode;
  mtu: number;
  delayTestUrl: string;
}

export interface SettingsStoreSnapshot {
  settings: AppSettings;
  saving: boolean;
}

export type SettingsStoreListener = (snapshot: SettingsStoreSnapshot) => void;

export const DEFAULT_APP_SETTINGS: AppSettings = {
  themeMode: AppThemeMode.SYSTEM,
  mtu: 1400,
  delayTestUrl: 'https://www.gstatic.com/generate_204'
};
