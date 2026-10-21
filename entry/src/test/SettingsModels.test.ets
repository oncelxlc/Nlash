import { describe, expect, it } from '@ohos/hypium';
import { DEFAULT_APP_SETTINGS, NAVIGATION_TRANSITION_OPTIONS } from '../main/ets/constants/SettingsConstants';
import { RUNTIME_REFRESH_INTERVAL_MS } from '../main/ets/constants/RuntimeConstants';
import { normalizeAppSettings, parseAppearanceSettings, resolveNavigationTransition } from '../main/ets/utils/SettingsUtils';
import { AppThemeMode, NavigationTransition, ThemeColorStyle, AppFont } from '../main/ets/model/SettingsModels';
import { normalizeThemeColor, resolveAppTheme, themeContrast, themeFontSize } from '../main/ets/utils/ThemeUtils';
import { THEME_COLORS, THEME_COLOR_STYLES } from '../main/ets/constants/ThemeConstants';
import { ThemeColorOption } from '../main/ets/model/ThemeModels';

export default function settingsModelsTest() {
  describe('settingsModels', () => {
    it('resolvesNavigationTransitionsAndMigratesMissingSettings', 0, () => {
      expect(DEFAULT_APP_SETTINGS.navigationTransition).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('NONE')).assertEqual(NavigationTransition.FADE);
      expect(NAVIGATION_TRANSITION_OPTIONS.length).assertEqual(2);
      expect(NAVIGATION_TRANSITION_OPTIONS[0]).assertEqual(NavigationTransition.FADE);
      expect(NAVIGATION_TRANSITION_OPTIONS[1]).assertEqual(NavigationTransition.SLIDE);
      expect(resolveNavigationTransition('FADE')).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('SLIDE')).assertEqual(NavigationTransition.SLIDE);
      expect(resolveNavigationTransition('')).assertEqual(NavigationTransition.FADE);
      expect(resolveNavigationTransition('unknown')).assertEqual(NavigationTransition.FADE);
    });

    it('usesOneFixedTwoSecondRefreshInterval', 0, () => {
      expect(RUNTIME_REFRESH_INTERVAL_MS).assertEqual(2000);
    });

    it('migratesMissingAndMalformedAppearanceWithoutChangingNetworkSettings', 0, () => {
      ['{}', 'null', '[]', 'invalid', '{"themeColor":12,"customFontScale":-1,"fontFamily":false}']
        .forEach((value: string): void => {
          const settings = parseAppearanceSettings(value);
          expect(settings.pureBlack).assertFalse();
          expect(settings.themeColor).assertEqual(DEFAULT_APP_SETTINGS.themeColor);
          expect(settings.followSystemFontScale).assertTrue();
          expect(settings.customFontScale).assertEqual(1);
          expect(settings.fontFamily).assertEqual(AppFont.SYSTEM);
        });
      const original = normalizeAppSettings(DEFAULT_APP_SETTINGS);
      original.mtu = 1500;
      original.delayTestUrl = 'https://example.com/test';
      original.pureBlack = true;
      original.themeColor = '#abcdef';
      original.customThemeColor = '#abcdef';
      original.fontFamily = AppFont.MONOSPACE;
      original.themeColorStyle = ThemeColorStyle.TONAL;
      original.followSystemFontScale = false;
      original.customFontScale = 1.65;
      const saved = parseAppearanceSettings(JSON.stringify(original));
      expect(saved.themeColor).assertEqual('#ABCDEF');
      expect(saved.customThemeColor).assertEqual('#ABCDEF');
      expect(saved.pureBlack).assertTrue();
      expect(saved.fontFamily).assertEqual(AppFont.MONOSPACE);
      expect(saved.customFontScale).assertEqual(1.65);
      expect(saved.mtu).assertEqual(1500);
      expect(saved.delayTestUrl).assertEqual(original.delayTestUrl);
    });

    it('resolvesSystemModeAndOnlyUsesPureBlackInDarkMode', 0, () => {
      const settings = normalizeAppSettings(DEFAULT_APP_SETTINGS);
      settings.pureBlack = true;
      expect(resolveAppTheme(settings, false).dark).assertFalse();
      expect(resolveAppTheme(settings, true).background).assertEqual('#000000');
      settings.themeMode = AppThemeMode.LIGHT;
      expect(resolveAppTheme(settings, true).dark).assertFalse();
      settings.themeMode = AppThemeMode.DARK;
      expect(resolveAppTheme(settings, false).background).assertEqual('#000000');
      settings.pureBlack = false;
      expect(resolveAppTheme(settings).background).assertEqual('#111113');
    });

    it('keepsReadableAccentsAcrossAllSwatchesStylesAndModes', 0, () => {
      const settings = normalizeAppSettings(DEFAULT_APP_SETTINGS);
      [AppThemeMode.LIGHT, AppThemeMode.DARK].forEach((mode: AppThemeMode): void => {
        settings.themeMode = mode;
        THEME_COLOR_STYLES.forEach((style: ThemeColorStyle): void => {
          settings.themeColorStyle = style;
          THEME_COLORS.concat([{ label: '白', value: '#FFFFFF' }, { label: '黑', value: '#000000' }])
            .forEach((color: ThemeColorOption): void => {
              settings.themeColor = color.value;
              const theme = resolveAppTheme(settings);
              expect(themeContrast(theme.accent, theme.surface) >= 4.5).assertTrue();
              expect(themeContrast(theme.accent, theme.onAccent) >= 4.5).assertTrue();
              expect(themeContrast(theme.accent, theme.accentSurface) >= 4.5).assertTrue();
            });
        });
      });
    });

    it('validatesCustomColorsAndRestoresSystemTextScaling', 0, () => {
      expect(normalizeThemeColor(' #12abef ')).assertEqual('#12ABEF');
      ['red', '#abc', '#12345678', '#GGGGGG', ''].forEach((value: string): void => {
        expect(normalizeThemeColor(value)).assertUndefined();
      });
      const settings = normalizeAppSettings(DEFAULT_APP_SETTINGS);
      expect(themeFontSize(16, resolveAppTheme(settings))).assertEqual(16);
      settings.followSystemFontScale = false;
      settings.customFontScale = 2;
      expect(themeFontSize(16, resolveAppTheme(settings))).assertEqual('32vp');
      settings.followSystemFontScale = true;
      expect(themeFontSize(16, resolveAppTheme(settings))).assertEqual(16);
      settings.customFontScale = 10;
      expect(normalizeAppSettings(settings).customFontScale).assertEqual(1);
    });
  });
}
