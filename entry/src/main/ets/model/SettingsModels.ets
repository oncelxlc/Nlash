export enum AppThemeMode {
  SYSTEM = 'SYSTEM',
  LIGHT = 'LIGHT',
  DARK = 'DARK'
}

export enum NavigationTransition {
  NONE = 'NONE',
  FADE = 'FADE',
  SLIDE = 'SLIDE'
}

export interface AppSettings {
  themeMode: AppThemeMode;
  navigationTransition: NavigationTransition;
  mtu: number;
  delayTestUrl: string;
  refreshIntervalSeconds: number;
}

export interface SettingsStoreSnapshot {
  settings: AppSettings;
  saving: boolean;
}

export type SettingsStoreListener = (snapshot: SettingsStoreSnapshot) => void;
