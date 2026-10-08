import { AppThemeMode, AppSettings, NavigationTransition } from '../model/SettingsModels';

export const REFRESH_INTERVAL_OPTIONS: number[] = [3, 5, 10, 30];
export const NAVIGATION_TRANSITION_OPTIONS: NavigationTransition[] = [
  NavigationTransition.NONE, NavigationTransition.FADE, NavigationTransition.SLIDE
];

export const DEFAULT_APP_SETTINGS: AppSettings = {
  themeMode: AppThemeMode.SYSTEM,
  navigationTransition: NavigationTransition.FADE,
  mtu: 1400,
  delayTestUrl: 'https://www.gstatic.com/generate_204',
  refreshIntervalSeconds: 3
};
