import { REFRESH_INTERVAL_OPTIONS } from '../constants/SettingsConstants';

export function isRefreshIntervalSeconds(value: number): boolean {
  return REFRESH_INTERVAL_OPTIONS.includes(value);
}

export function resolveRefreshIntervalMilliseconds(value: number): number {
  const seconds = isRefreshIntervalSeconds(value) ? value : 3;
  return seconds * 1000;
}
