/** 页面共享的语义颜色；业务成功、警告和错误色继续使用系统深浅色资源。 */
export interface AppTheme {
  dark: boolean;
  background: string;
  transparentBackground: string;
  surface: string;
  inset: string;
  muted: string;
  divider: string;
  accent: string;
  onAccent: string;
  accentSurface: string;
  accentSecondary: string;
  accentGlow: string;
  fontFamily: string;
  fontScale: number;
}

export interface ThemeColorOption {
  label: string;
  value: string;
}
