import { DashboardCard } from '../model/DashboardModels';

// 同时作为默认顺序和合法卡片集合，恢复旧布局时据此补齐新增卡片。
export const DEFAULT_DASHBOARD_CARD_ORDER: DashboardCard[] = [
  DashboardCard.MODE, DashboardCard.CONFIGURATION, DashboardCard.SPEED, DashboardCard.PUBLIC_NETWORK,
  DashboardCard.TRAFFIC, DashboardCard.DURATION, DashboardCard.CONNECTIONS, DashboardCard.MEMORY
];
