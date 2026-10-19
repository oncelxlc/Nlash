import { DEFAULT_DASHBOARD_CARD_ORDER } from '../constants/DashboardConstants';
import { DashboardCard } from '../model/DashboardModels';

/** 用户保存顺序优先；展开屏将信息卡片配成两列。 */
export function resolveDashboardCardOrder(cards: DashboardCard[] | undefined, compact: boolean): DashboardCard[] {
  if (cards !== undefined) {
    return normalizeDashboardCardOrder(cards);
  }
  const defaults = DEFAULT_DASHBOARD_CARD_ORDER.slice();
  return compact ? defaults : moveDashboardCard(defaults, defaults.indexOf(DashboardCard.MEMORY),
    defaults.indexOf(DashboardCard.GROUPS));
}

/** 丢弃未知 ID，保留已保存卡片的相对顺序，并在末尾补上新增默认卡片。 */
export function normalizeDashboardCardOrder(ids: string[]): DashboardCard[] {
  const merged = ids.map((id: string): string => id === DashboardCard.TRAFFIC ? DashboardCard.SPEED :
    (id === DashboardCard.DURATION ? DashboardCard.PUBLIC_NETWORK : id));
  return DEFAULT_DASHBOARD_CARD_ORDER.slice().sort((left: DashboardCard, right: DashboardCard): number => {
    const leftIndex = merged.indexOf(left);
    const rightIndex = merged.indexOf(right);
    return (leftIndex < 0 ? merged.length : leftIndex) - (rightIndex < 0 ? merged.length : rightIndex);
  });
}

export function moveDashboardCard(cards: DashboardCard[], from: number, to: number): DashboardCard[] {
  const result = cards.slice();
  if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || from >= result.length ||
    to < 0 || to >= result.length || from === to) {
    return result;
  }
  const moved = result.splice(from, 1)[0];
  result.splice(to, 0, moved);
  return result;
}

/** 两列栅格的列跨度；卡片高度随内容和系统字号增长。 */
export function dashboardCardSpan(card: DashboardCard, compact: boolean = false): [number, number] {
  if (compact || card === DashboardCard.PUBLIC_NETWORK || card === DashboardCard.SPEED ||
    card === DashboardCard.MODE || card === DashboardCard.VPN || card === DashboardCard.CONNECTIONS) {
    return [2, 1];
  }
  return [1, 1];
}

export function dashboardCardLabel(card: DashboardCard): string {
  switch (card) {
    case DashboardCard.MODE: return '出站模式';
    case DashboardCard.CONFIGURATION: return '配置';
    case DashboardCard.SPEED: return '网络速度';
    case DashboardCard.PUBLIC_NETWORK: return '状态';
    case DashboardCard.TRAFFIC: return '流量统计';
    case DashboardCard.DURATION: return '运行时长';
    case DashboardCard.CONNECTIONS: return '活动统计';
    case DashboardCard.MEMORY: return '内存信息';
    case DashboardCard.VPN: return 'VPN';
    case DashboardCard.SERVICES: return '服务状态';
    case DashboardCard.GROUPS: return '策略组';
  }
}
