/** 持久化的仪表盘卡片标识；旧标识在恢复布局时合并到对应卡片。 */
export enum DashboardCard {
  MODE = 'mode',
  CONFIGURATION = 'configuration',
  SPEED = 'speed',
  PUBLIC_NETWORK = 'publicNetwork',
  TRAFFIC = 'traffic',
  DURATION = 'duration',
  CONNECTIONS = 'connections',
  MEMORY = 'memory',
  VPN = 'vpn',
  SERVICES = 'services',
  GROUPS = 'groups'
}
