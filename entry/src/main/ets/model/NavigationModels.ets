/** 保留旧活动页跳转目标，诊断与资源页面从设置独立进入。 */
export enum AppPage {
  DASHBOARD,
  PROXY,
  CONFIGURATION,
  REQUESTS,
  CONNECTIONS,
  SETTINGS,
  ACTIVITY,
  DNS,
  RESOURCES,
  THEME,
  GENERAL,
  ABOUT
}

export enum ActivityTab {
  CONNECTIONS,
  REQUESTS
}

export enum RequestFilter {
  ALL = 'ALL',
  ACTIVE = 'ACTIVE',
  COMPLETED = 'COMPLETED'
}
