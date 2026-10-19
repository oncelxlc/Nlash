import { DashboardCard } from '../model/DashboardModels';

// 手机固定顺序；展开屏仅调整信息卡片的配对。
export const DEFAULT_DASHBOARD_CARD_ORDER: DashboardCard[] = [
  DashboardCard.PUBLIC_NETWORK, DashboardCard.SPEED, DashboardCard.MODE, DashboardCard.VPN,
  DashboardCard.SERVICES, DashboardCard.CONFIGURATION, DashboardCard.GROUPS,
  DashboardCard.CONNECTIONS, DashboardCard.MEMORY
];

export const DASHBOARD_CARD_RADIUS: number = 32;
export const DASHBOARD_CARD_PADDING: number = 20;
