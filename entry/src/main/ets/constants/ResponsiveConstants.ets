import { ResponsiveSizeClass, ResponsiveMetrics } from '../model/ResponsiveModels';

export const COMPACT_METRICS: ResponsiveMetrics = {
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
  proxyColumns: '1fr 1fr'
};

export const MEDIUM_METRICS: ResponsiveMetrics = {
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
  proxyColumns: '1fr 1fr'
};

export const EXPANDED_METRICS: ResponsiveMetrics = {
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
  proxyColumns: '1fr 1fr 1fr 1fr'
};
