import { DEFAULT_APP_SETTINGS, NAVIGATION_TRANSITION_OPTIONS } from '../constants/SettingsConstants';
import { NavigationTransition } from '../model/SettingsModels';

/** 已保存值可能来自旧版本或异常数据，未知过渡类型回退到项目默认值。 */
export function resolveNavigationTransition(value: string): NavigationTransition {
  return NAVIGATION_TRANSITION_OPTIONS.find((transition: NavigationTransition): boolean => transition === value) ??
    DEFAULT_APP_SETTINGS.navigationTransition;
}
