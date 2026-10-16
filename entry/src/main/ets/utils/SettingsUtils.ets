import { DEFAULT_APP_SETTINGS, NAVIGATION_TRANSITION_OPTIONS } from '../constants/SettingsConstants';
import { NavigationTransition } from '../model/SettingsModels';

export function resolveNavigationTransition(value: string): NavigationTransition {
  return NAVIGATION_TRANSITION_OPTIONS.find((transition: NavigationTransition): boolean => transition === value) ??
    DEFAULT_APP_SETTINGS.navigationTransition;
}
