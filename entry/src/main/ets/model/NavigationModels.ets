/** 保留请求与连接的独立跳转目标，统一进入设置下的活动页。 */
export enum AppPage {
  DASHBOARD,
  PROXY,
  CONFIGURATION,
  REQUESTS,
  CONNECTIONS,
  SETTINGS,
  ACTIVITY
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
