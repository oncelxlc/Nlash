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
  proxyColumns: string;
}
