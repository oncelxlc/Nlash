import { AppThemeMode, AppSettings } from '../model/SettingsModels';

export const REFRESH_INTERVAL_OPTIONS: number[] = [3, 5, 10, 30];

export const DEFAULT_APP_SETTINGS: AppSettings = {
  themeMode: AppThemeMode.SYSTEM,
  mtu: 1400,
  delayTestUrl: 'https://www.gstatic.com/generate_204',
  refreshIntervalSeconds: 3
};
