/** 保留请求与连接的独立跳转目标，实际一级入口统一映射到 ACTIVITY。 */
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
