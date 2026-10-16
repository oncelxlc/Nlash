export enum AppThemeMode {
  SYSTEM = 'SYSTEM',
  LIGHT = 'LIGHT',
  DARK = 'DARK'
}

export enum NavigationTransition {
  FADE = 'FADE',
  SLIDE = 'SLIDE'
}

export interface AppSettings {
  themeMode: AppThemeMode;
  navigationTransition: NavigationTransition;
  mtu: number;
  delayTestUrl: string;
}

export interface SettingsStoreSnapshot {
  settings: AppSettings;
  saving: boolean;
}

export type SettingsStoreListener = (snapshot: SettingsStoreSnapshot) => void;
