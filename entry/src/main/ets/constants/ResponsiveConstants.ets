import { ResponsiveSizeClass, ResponsiveMetrics } from '../model/ResponsiveModels';

// 各档位复用同一字段集合，窗口宽度变化时由 ResponsiveUtils 整体选择。
export const COMPACT_METRICS: ResponsiveMetrics = {
  sizeClass: ResponsiveSizeClass.COMPACT,
  pagePadding: 16,
  sectionGap: 16,
  cardGap: 12,
  profileColumns: '1fr',
  dashboardColumns: '1fr',
  profileCardWidth: '100%',
  dashboardCardWidth: '100%',
  dashboardCardHeight: 96,
  dashboardInfoCardHeight: 88,
  proxyColumns: '1fr 1fr'
};

export const MEDIUM_METRICS: ResponsiveMetrics = {
  sizeClass: ResponsiveSizeClass.MEDIUM,
  pagePadding: 24,
  sectionGap: 24,
  cardGap: 12,
  profileColumns: '1fr 1fr',
  dashboardColumns: '1fr 1fr',
  profileCardWidth: '48%',
  dashboardCardWidth: '48%',
  dashboardCardHeight: 96,
  dashboardInfoCardHeight: 88,
  proxyColumns: '1fr 1fr 1fr'
};

export const EXPANDED_METRICS: ResponsiveMetrics = {
  sizeClass: ResponsiveSizeClass.EXPANDED,
  pagePadding: 32,
  sectionGap: 24,
  cardGap: 12,
  profileColumns: '1fr 1fr',
  dashboardColumns: '1fr 1fr',
  profileCardWidth: '48%',
  dashboardCardWidth: '48%',
  dashboardCardHeight: 96,
  dashboardInfoCardHeight: 88,
  proxyColumns: '1fr 1fr 1fr 1fr'
};
