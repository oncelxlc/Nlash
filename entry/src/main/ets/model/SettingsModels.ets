export enum AppThemeMode {
  SYSTEM = 'SYSTEM',
  LIGHT = 'LIGHT',
  DARK = 'DARK'
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
