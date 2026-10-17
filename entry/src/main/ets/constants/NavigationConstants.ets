import { AppPage } from '../model/NavigationModels';

// 数组位置对应底部标签索引；请求和连接统一从 ACTIVITY 的二级标签进入。
export const NAVIGATION_PAGES: AppPage[] = [
  AppPage.DASHBOARD,
  AppPage.PROXY,
  AppPage.CONFIGURATION,
  AppPage.ACTIVITY,
  AppPage.SETTINGS
];
