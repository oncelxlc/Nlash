import { DEFAULT_APP_SETTINGS, NAVIGATION_TRANSITION_OPTIONS, REFRESH_INTERVAL_OPTIONS } from '../constants/SettingsConstants';
import { NavigationTransition } from '../model/SettingsModels';

export function resolveNavigationTransition(value: string): NavigationTransition {
  return NAVIGATION_TRANSITION_OPTIONS.find((transition: NavigationTransition): boolean => transition === value) ??
    DEFAULT_APP_SETTINGS.navigationTransition;
}

export function isRefreshIntervalSeconds(value: number): boolean {
  return REFRESH_INTERVAL_OPTIONS.includes(value);
}

export function resolveRefreshIntervalMilliseconds(value: number): number {
  const seconds = isRefreshIntervalSeconds(value) ? value : 3;
  return seconds * 1000;
}
