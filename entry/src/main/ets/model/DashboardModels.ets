/** 仪表盘固定卡片标识。 */
export enum DashboardCard {
  MODE = 'mode',
  CONFIGURATION = 'configuration',
  SPEED = 'speed',
  PUBLIC_NETWORK = 'publicNetwork',
  CONNECTIONS = 'connections',
  MEMORY = 'memory',
  VPN = 'vpn',
  SERVICES = 'services',
  GROUPS = 'groups'
}

/** 应用进程与 Mihomo 的内存统计，单位为字节；缺失数据不按零处理。 */
export interface DashboardMemoryUsage {
  appBytes?: number;
  coreBytes?: number;
  totalBytes?: number;
  appRatio: number;
}
