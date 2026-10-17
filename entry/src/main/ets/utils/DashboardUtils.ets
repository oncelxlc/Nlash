import { DEFAULT_DASHBOARD_CARD_ORDER } from '../constants/DashboardConstants';
import { DashboardCard } from '../model/DashboardModels';

/** 用户保存顺序优先；仅未自定义布局的窄屏将公网出口卡片前移。 */
export function resolveDashboardCardOrder(cards: DashboardCard[] | undefined, compact: boolean): DashboardCard[] {
  if (cards !== undefined) {
    return cards.slice();
  }
  const defaults = DEFAULT_DASHBOARD_CARD_ORDER.slice();
  return compact ? moveDashboardCard(defaults, defaults.indexOf(DashboardCard.PUBLIC_NETWORK),
    defaults.indexOf(DashboardCard.SPEED)) : defaults;
}

/** 丢弃未知 ID，保留已保存卡片的相对顺序，并在末尾补上新增默认卡片。 */
export function normalizeDashboardCardOrder(ids: string[]): DashboardCard[] {
  return DEFAULT_DASHBOARD_CARD_ORDER.slice().sort((left: DashboardCard, right: DashboardCard): number => {
    const leftIndex = ids.indexOf(left);
    const rightIndex = ids.indexOf(right);
    return (leftIndex < 0 ? ids.length : leftIndex) - (rightIndex < 0 ? ids.length : rightIndex);
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

/** 返回逻辑网格中的 [列跨度, 行跨度]，实际尺寸由页面按网格单位换算。 */
export function dashboardCardSpan(card: DashboardCard): [number, number] {
  if (card === DashboardCard.MODE || card === DashboardCard.SPEED || card === DashboardCard.TRAFFIC) {
    return [2, card === DashboardCard.SPEED ? 2 : 1];
  }
  return [1, 1];
}

export function dashboardCardLabel(card: DashboardCard): string {
  switch (card) {
    case DashboardCard.MODE: return '出站模式';
    case DashboardCard.CONFIGURATION: return '配置';
    case DashboardCard.SPEED: return '网络速度';
    case DashboardCard.PUBLIC_NETWORK: return '公网出口';
    case DashboardCard.TRAFFIC: return '流量统计';
    case DashboardCard.DURATION: return '运行时长';
    case DashboardCard.CONNECTIONS: return '活动连接';
    case DashboardCard.MEMORY: return 'Core 内存';
  }
}
