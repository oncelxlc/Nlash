import { AppThemeMode, AppSettings, NavigationTransition } from '../model/SettingsModels';

export const NAVIGATION_TRANSITION_OPTIONS: NavigationTransition[] = [
  NavigationTransition.FADE, NavigationTransition.SLIDE
];

// 首次启动及异常持久化值的回退来源，避免页面与仓库各自维护一套默认值。
export const DEFAULT_APP_SETTINGS: AppSettings = {
  themeMode: AppThemeMode.SYSTEM,
  navigationTransition: NavigationTransition.FADE,
  mtu: 1400,
  delayTestUrl: 'https://www.gstatic.com/generate_204'
};
