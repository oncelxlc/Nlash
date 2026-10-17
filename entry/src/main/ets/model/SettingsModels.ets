export enum AppThemeMode {
  SYSTEM = 'SYSTEM',
  LIGHT = 'LIGHT',
  DARK = 'DARK'
}

export enum NavigationTransition {
  FADE = 'FADE',
  SLIDE = 'SLIDE'
}

/** 持久化应用设置；MTU 在下一次创建 TUN 时读取，delayTestUrl 用于手动测速。 */
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
