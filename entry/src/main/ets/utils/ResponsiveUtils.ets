import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { COMPACT_METRICS, MEDIUM_METRICS, EXPANDED_METRICS } from '../constants/ResponsiveConstants';

export function resolveContentWidth(width: Length): number {
  const numericWidth = typeof width === 'number' ? width : (typeof width === 'string' ? Number(width) : 0);
  return Number.isFinite(numericWidth) ? numericWidth : 0;
}

/** 按实际内容宽度选择档位，折叠展开或分屏后可重新计算，不依赖设备型号。 */
export function resolveResponsiveMetrics(contentWidth: number, forceExpanded: boolean = false): ResponsiveMetrics {
  if (forceExpanded || contentWidth >= 900) {
    return EXPANDED_METRICS;
  }
  if (contentWidth >= 640) {
    return MEDIUM_METRICS;
  }
  return COMPACT_METRICS;
}

export function resolveDashboardSpeedCardHeight(metrics: ResponsiveMetrics): number {
  return metrics.dashboardCardHeight * 2 + metrics.cardGap;
}

export function resolveDashboardTrafficCardHeight(metrics: ResponsiveMetrics): number {
  return metrics.dashboardInfoCardHeight * 2 + metrics.cardGap;
}

/** 宽屏分为两列，较大字号时优先保证组头与操作可读。 */
export function proxyGroupColumnCount(contentWidth: number, fontScale: number = 1): number {
  return contentWidth >= 640 * Math.max(1, fontScale) ? 2 : 1;
}

export function proxyNodeColumnCount(groupWidth: number, fontScale: number = 1): number {
  return groupWidth >= 280 * Math.max(1, fontScale) ? 2 : 1;
}
