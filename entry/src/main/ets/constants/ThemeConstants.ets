import { ThemeColorOption } from '../model/ThemeModels';
import { AppFont, AppThemeMode, ThemeColorStyle } from '../model/SettingsModels';

export const THEME_MODES: AppThemeMode[] = [AppThemeMode.SYSTEM, AppThemeMode.LIGHT, AppThemeMode.DARK];
export const THEME_MODE_LABELS: string[] = ['自动', '浅色', '深色'];
export const THEME_COLOR_STYLES: ThemeColorStyle[] = [
  ThemeColorStyle.VIVID, ThemeColorStyle.TONAL, ThemeColorStyle.MONOCHROME
];
export const THEME_COLOR_STYLE_LABELS: string[] = ['鲜明', '柔和', '单色'];
export const THEME_FONTS: AppFont[] = [AppFont.SYSTEM, AppFont.SANS, AppFont.SERIF, AppFont.MONOSPACE];
export const THEME_FONT_LABELS: string[] = ['默认', 'HarmonyOS Sans', '衬线字体', '等宽字体'];
export const MIN_CUSTOM_FONT_SCALE: number = 0.85;
export const MAX_CUSTOM_FONT_SCALE: number = 2;
export const THEME_COLORS: ThemeColorOption[] = [
  { label: '系统强调色', value: 'SYSTEM' },
  { label: '蓝色', value: '#2F80FF' },
  { label: '紫色', value: '#B34DDB' },
  { label: '粉色', value: '#FF2867' },
  { label: '红色', value: '#F44336' },
  { label: '橙色', value: '#FF9800' },
  { label: '黄色', value: '#FFC800' },
  { label: '绿色', value: '#30C759' },
  { label: '灰色', value: '#8E8E93' }
];
