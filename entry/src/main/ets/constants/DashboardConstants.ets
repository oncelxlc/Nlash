import { DashboardCard } from '../model/DashboardModels';

// 同时作为默认顺序和合法卡片集合，恢复旧布局时据此补齐新增卡片。
export const DEFAULT_DASHBOARD_CARD_ORDER: DashboardCard[] = [
  DashboardCard.PUBLIC_NETWORK, DashboardCard.SPEED, DashboardCard.MODE, DashboardCard.VPN,
  DashboardCard.SERVICES, DashboardCard.CONFIGURATION, DashboardCard.GROUPS,
  DashboardCard.CONNECTIONS, DashboardCard.MEMORY
];

export const DASHBOARD_CARD_RADIUS: number = 32;
export const DASHBOARD_CARD_PADDING: number = 20;
