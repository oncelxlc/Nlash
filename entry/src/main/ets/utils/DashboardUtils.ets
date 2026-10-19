import { DEFAULT_DASHBOARD_CARD_ORDER } from '../constants/DashboardConstants';
import { DashboardCard, DashboardMemoryUsage } from '../model/DashboardModels';

/** 固定默认排序，展开屏将内存信息与策略组配成一行。 */
export function resolveDashboardCardOrder(compact: boolean): DashboardCard[] {
  const cards = DEFAULT_DASHBOARD_CARD_ORDER.slice();
  if (!compact) {
    cards.splice(cards.indexOf(DashboardCard.MEMORY), 1);
    cards.splice(cards.indexOf(DashboardCard.GROUPS), 0, DashboardCard.MEMORY);
  }
  return cards;
}

/** 两列栅格的列跨度；卡片高度随内容和系统字号增长。 */
export function dashboardCardSpan(card: DashboardCard, compact: boolean): number {
  return compact || card === DashboardCard.PUBLIC_NETWORK || card === DashboardCard.SPEED ||
    card === DashboardCard.MODE || card === DashboardCard.VPN || card === DashboardCard.CONNECTIONS ? 2 : 1;
}

export function dashboardMemoryUsage(appBytes?: number, coreBytes?: number): DashboardMemoryUsage {
  const app = appBytes !== undefined && Number.isFinite(appBytes) && appBytes >= 0 ? appBytes : undefined;
  const core = coreBytes !== undefined && Number.isFinite(coreBytes) && coreBytes >= 0 ? coreBytes : undefined;
  const sum = app !== undefined && core !== undefined ? app + core : undefined;
  const total = sum !== undefined && Number.isFinite(sum) ? sum : undefined;
  return { appBytes: app, coreBytes: core, totalBytes: total,
    appRatio: total !== undefined && total > 0 ? (app ?? 0) / total : 0 };
}

export function formatMemoryMegabytes(bytes: number | undefined): string {
  return bytes === undefined || !Number.isFinite(bytes) || bytes < 0 ? '—' : (bytes / 1048576).toFixed(1);
}

/** 波浪仅表示订阅已用比例，不构造流量趋势；尺寸为 Path 使用的像素。 */
export function buildSubscriptionUsageWave(width: number, height: number, ratio: number): string {
  if (!Number.isFinite(width) || !Number.isFinite(height) || !Number.isFinite(ratio) ||
    width <= 0 || height <= 0 || ratio <= 0) {
    return '';
  }
  const usedWidth = width * Math.min(1, ratio);
  const center = height / 2;
  const step = height / 2;
  let path = `M 0 ${center}`;
  let direction = 1;
  for (let x = 0; x < usedWidth; x += step) {
    const end = Math.min(x + step, usedWidth);
    path += ` Q ${(x + end) / 2} ${center + direction * height * 0.6} ${end} ${center}`;
    direction *= -1;
  }
  return path;
}
