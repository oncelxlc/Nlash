export enum ResponsiveSizeClass {
  COMPACT = 'COMPACT',
  MEDIUM = 'MEDIUM',
  EXPANDED = 'EXPANDED'
}

/** 各窗口宽度档位共用的布局参数，数值尺寸为 vp，列模板用于 ArkUI 网格。 */
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
