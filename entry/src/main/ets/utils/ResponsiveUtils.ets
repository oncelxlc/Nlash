import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { COMPACT_METRICS, MEDIUM_METRICS, EXPANDED_METRICS } from '../constants/ResponsiveConstants';

export function resolveContentWidth(width: Length): number {
  const numericWidth = typeof width === 'number' ? width : (typeof width === 'string' ? Number(width) : 0);
  return Number.isFinite(numericWidth) ? numericWidth : 0;
}

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
