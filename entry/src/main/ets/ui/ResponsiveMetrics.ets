export enum ResponsiveSizeClass {
  COMPACT = 'COMPACT',
  MEDIUM = 'MEDIUM',
  EXPANDED = 'EXPANDED'
}

export interface ResponsiveMetrics {
  sizeClass: ResponsiveSizeClass;
  pagePadding: number;
  sectionGap: number;
  cardGap: number;
  profileColumns: string;
  dashboardColumns: string;
  profileCardWidth: string;
  dashboardCardWidth: string;
  dashboardCardHeight: number;
  dashboardInfoCardHeight: number;
  proxyCardWidth: string;
}

const COMPACT_METRICS: ResponsiveMetrics = {
  sizeClass: ResponsiveSizeClass.COMPACT,
  pagePadding: 16,
  sectionGap: 18,
  cardGap: 12,
  profileColumns: '1fr',
  dashboardColumns: '1fr',
  profileCardWidth: '100%',
  dashboardCardWidth: '100%',
  dashboardCardHeight: 112,
  dashboardInfoCardHeight: 100,
  proxyCardWidth: '49%'
};

const MEDIUM_METRICS: ResponsiveMetrics = {
  sizeClass: ResponsiveSizeClass.MEDIUM,
  pagePadding: 24,
  sectionGap: 22,
  cardGap: 12,
  profileColumns: '1fr 1fr',
  dashboardColumns: '1fr 1fr',
  profileCardWidth: '48%',
  dashboardCardWidth: '48%',
  dashboardCardHeight: 112,
  dashboardInfoCardHeight: 100,
  proxyCardWidth: '49%'
};

const EXPANDED_METRICS: ResponsiveMetrics = {
  sizeClass: ResponsiveSizeClass.EXPANDED,
  pagePadding: 16,
  sectionGap: 24,
  cardGap: 12,
  profileColumns: '1fr 1fr',
  dashboardColumns: '1fr 1fr',
  profileCardWidth: '48%',
  dashboardCardWidth: '48%',
  dashboardCardHeight: 112,
  dashboardInfoCardHeight: 104,
  proxyCardWidth: '24%'
};

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
