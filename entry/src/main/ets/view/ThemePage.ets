import { LengthMetrics } from '@kit.ArkUI';
import { AppSettings, AppThemeMode, NavigationTransition, SettingsStoreSnapshot } from '../model/SettingsModels';
import { AppTheme, ThemeColorOption } from '../model/ThemeModels';
import { settingsStore } from '../stores/SettingsStore';
import {
  THEME_MODES, THEME_MODE_LABELS, THEME_COLORS, THEME_COLOR_STYLES, THEME_COLOR_STYLE_LABELS,
  THEME_FONTS, THEME_FONT_LABELS, MIN_CUSTOM_FONT_SCALE, MAX_CUSTOM_FONT_SCALE
} from '../constants/ThemeConstants';
import { DEFAULT_APP_THEME, resolveAppTheme, themeContrast, themeFontSize } from '../utils/ThemeUtils';
import { normalizeAppSettings } from '../utils/SettingsUtils';
import { resolveContentWidth, resolveResponsiveMetrics } from '../utils/ResponsiveUtils';
import { FadingScrollLayout } from '../components/FadingScrollLayout';
import { SecondaryPageHeader } from '../components/SecondaryPageHeader';
import { SingleChoiceControl } from '../components/SingleChoiceControl';
import { ThemePreview } from '../components/ThemePreview';
import { ThemeColorDialog } from '../components/ThemeColorDialog';

interface ThemeChoiceRowParams {
  label: string;
  selected: boolean;
  palette: AppTheme;
  action: () => void;
  last: boolean;
}

@Component
export struct ThemePage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  onBack: () => void = (): void => {};
  @State settings: AppSettings = settingsStore.getSnapshot().settings;
  @State errorMessage: string = '';
  @State headerInset: number = 0;
  @State contentPadding: number = 16;
  @State scaleDraft: number = Math.round(settingsStore.getSnapshot().settings.customFontScale * 100);
  private unsubscribe: (() => void) | undefined = undefined;
  private colorDialog: CustomDialogController = new CustomDialogController({
    builder: ThemeColorDialog({
      initialColor: this.settings.customThemeColor,
      onSubmit: async (color: string): Promise<void> => {
        await settingsStore.updateAppearance((next: AppSettings): void => {
          next.customThemeColor = color;
          next.themeColor = color;
        });
      }
    }),
    customStyle: true,
    autoCancel: false
  });

  aboutToAppear(): void {
    this.unsubscribe = settingsStore.subscribe((snapshot: SettingsStoreSnapshot): void => {
      // 保存期间保留当前外观；后台队列按顺序合并各选项。
      if (snapshot.saving) { return; }
      if (this.settings.customFontScale !== snapshot.settings.customFontScale ||
        this.settings.followSystemFontScale !== snapshot.settings.followSystemFontScale) {
        this.scaleDraft = Math.round(snapshot.settings.customFontScale * 100);
      }
      this.settings = snapshot.settings;
    });
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.colorDialog.close();
  }

  private async update(change: (settings: AppSettings) => void): Promise<void> {
    this.errorMessage = '';
    try { await settingsStore.updateAppearance(change); }
    catch (error) { this.errorMessage = (error as Error).message || '主题保存失败，请重试'; }
  }

  private preview(mode: AppThemeMode, black: boolean = false): AppTheme {
    const next = normalizeAppSettings(this.settings);
    next.themeMode = mode;
    next.pureBlack = black;
    return resolveAppTheme(next, this.theme.dark, this.theme.accent);
  }

  private selectedFont(): string {
    return THEME_FONT_LABELS[THEME_FONTS.indexOf(this.settings.fontFamily)];
  }

  @Builder
  private sectionTitle(title: string, icon: Resource) {
    Row({ space: 12 }) {
      Image(icon).width(22).height(22).fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
      Text(title).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
        .fontColor($r('app.color.content_secondary'))
    }.width('100%').padding({ top: 16, bottom: 6 })
  }

  @Builder
  private choiceRow($$: ThemeChoiceRowParams) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        ThemePreview({ palette: $$.palette, miniature: true })
        Text($$.label).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_primary')).layoutWeight(1).textAlign(TextAlign.Start)
        if ($$.selected) {
          Image($r('app.media.action_check')).width(24).height(24).fillColor(this.theme.accent).accessibilityLevel('no')
        }
      }.width('100%')
    }.id(`theme-choice-${$$.label}`).width('100%').constraintSize({ minHeight: 68 })
      .padding({ left: 16, right: 16, top: 10, bottom: 10 })
      .backgroundColor(Color.Transparent).borderRadius(0)
      .accessibilityText($$.label).accessibilitySelected($$.selected).onClick($$.action)
    if (!$$.last) { Divider().color(this.theme.divider).margin({ left: 70, right: 16 }) }
  }

  @Builder
  private modes() {
    this.sectionTitle('主题模式', $r('app.media.theme_sun'))
    Column() {
      ForEach(THEME_MODES, (mode: AppThemeMode, index: number) => {
        this.choiceRow({ label: THEME_MODE_LABELS[index], selected: this.settings.themeMode === mode,
          palette: this.preview(mode), last: index === THEME_MODES.length - 1,
          action: (): void => { this.update((next: AppSettings): void => { next.themeMode = mode; }); }
        })
      })
    }.width('100%').backgroundColor(this.theme.surface).borderRadius(24).clip(true)
    this.sectionTitle('纯黑模式', $r('app.media.theme_moon'))
    Column() {
      this.choiceRow({ label: '标准', selected: !this.settings.pureBlack, palette: this.preview(AppThemeMode.DARK), last: false,
        action: (): void => { this.update((next: AppSettings): void => { next.pureBlack = false; }); }
      })
      this.choiceRow({ label: '纯黑', selected: this.settings.pureBlack, palette: this.preview(AppThemeMode.DARK, true), last: true,
        action: (): void => { this.update((next: AppSettings): void => { next.pureBlack = true; }); }
      })
    }.width('100%').backgroundColor(this.theme.surface).borderRadius(24).clip(true)
    Text('纯黑模式在深色外观下生效').fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily)
      .fontColor($r('app.color.content_secondary')).width('100%').padding({ left: 16 })
  }

  @Builder
  private colorChoice(option: ThemeColorOption) {
    Button({ type: ButtonType.Circle }) {
      Stack() {
        Row().borderRadius(100).width(32).height(32).backgroundColor(option.value === 'SYSTEM' ? '#A7B4FF' : option.value)
        if (this.settings.themeColor === option.value) {
          Image($r('app.media.action_check')).width(20).height(20)
            .fillColor(themeContrast(option.value === 'SYSTEM' ? '#A7B4FF' : option.value, '#FFFFFF') >= 4.5 ?
              '#FFFFFF' : '#111113').accessibilityLevel('no')
        } else if (option.value === 'SYSTEM') {
          Image($r('app.media.action_refresh')).width(18).height(18).fillColor('#202024').accessibilityLevel('no')
        }
      }
    }.id(`theme-color-${option.value}`).width(44).height(44).padding(0).backgroundColor(Color.Transparent)
      .border({ width: this.settings.themeColor === option.value ? 2 : 0, color: this.theme.accent })
      .accessibilityText(option.label).accessibilitySelected(this.settings.themeColor === option.value)
      .onClick((): void => { this.update((next: AppSettings): void => { next.themeColor = option.value; }); })
  }

  @Builder
  private colors() {
    this.sectionTitle('主题色彩', $r('app.media.theme_palette'))
    Flex({ wrap: FlexWrap.Wrap, space: { main: LengthMetrics.vp(6), cross: LengthMetrics.vp(8) } }) {
      ForEach(THEME_COLORS, (option: ThemeColorOption) => { this.colorChoice(option) })
      if (!THEME_COLORS.some((option: ThemeColorOption): boolean => option.value === this.settings.customThemeColor)) {
        this.colorChoice({ label: '已保存的自定义主题色', value: this.settings.customThemeColor })
      }
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.action_add')).width(22).height(22).fillColor($r('app.color.content_primary')).accessibilityLevel('no')
      }.id('theme-custom-color').width(44).height(44).padding(10).backgroundColor(this.theme.muted)
        .accessibilityText('自定义主题色').onClick((): void => {
          this.colorDialog.open();
        })
    }.width('100%').padding(12).borderRadius(24).backgroundColor(this.theme.surface)
    Row({ space: 12 }) {
      Text('配色风格').fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
        .fontColor($r('app.color.content_primary')).layoutWeight(1)
      Select(THEME_COLOR_STYLE_LABELS.map((label: string): SelectOption => { return { value: label }; }))
        .selected(THEME_COLOR_STYLES.indexOf(this.settings.themeColorStyle))
        .value(THEME_COLOR_STYLE_LABELS[THEME_COLOR_STYLES.indexOf(this.settings.themeColorStyle)])
        .font({ size: themeFontSize(16, this.theme), family: this.theme.fontFamily })
        .optionFont({ size: themeFontSize(16, this.theme), family: this.theme.fontFamily })
        .selectedOptionFont({ size: themeFontSize(16, this.theme), family: this.theme.fontFamily })
        .optionFontColor($r('app.color.content_primary')).selectedOptionFontColor(this.theme.accent)
        .optionBgColor(this.theme.surface).selectedOptionBgColor(this.theme.accentSurface)
        .menuBackgroundColor(this.theme.surface)
        .fontColor($r('app.color.content_secondary')).backgroundColor(Color.Transparent)
        .accessibilityText('配色风格').onSelect((index: number): void => {
          this.update((next: AppSettings): void => { next.themeColorStyle = THEME_COLOR_STYLES[index]; });
        })
    }.width('100%').padding(16).borderRadius(24).backgroundColor(this.theme.surface)
  }

  @Builder
  private animationSection() {
    this.sectionTitle('选项卡动画', $r('app.media.action_switch'))
    Column() {
      this.choiceRow({ label: '滑动', selected: this.settings.navigationTransition === NavigationTransition.SLIDE,
        palette: this.theme, last: false,
        action: (): void => { this.update((next: AppSettings): void => { next.navigationTransition = NavigationTransition.SLIDE; }); }
      })
      this.choiceRow({ label: '淡入', selected: this.settings.navigationTransition === NavigationTransition.FADE,
        palette: this.theme, last: true,
        action: (): void => { this.update((next: AppSettings): void => { next.navigationTransition = NavigationTransition.FADE; }); }
      })
    }.width('100%').backgroundColor(this.theme.surface).borderRadius(24).clip(true)
  }

  @Builder
  private typography() {
    this.sectionTitle('字体', $r('app.media.theme_type'))
    Row({ space: 12 }) {
      Text('Aa').fontSize(themeFontSize(18, this.theme)).fontFamily(this.theme.fontFamily)
        .fontColor($r('app.color.content_secondary')).accessibilityLevel('no')
      Select(THEME_FONT_LABELS.map((label: string): SelectOption => { return { value: label }; }))
        .id('theme-font').selected(THEME_FONTS.indexOf(this.settings.fontFamily)).value(this.selectedFont())
        .font({ size: themeFontSize(16, this.theme), family: this.theme.fontFamily })
        .optionFont({ size: themeFontSize(16, this.theme), family: this.theme.fontFamily })
        .selectedOptionFont({ size: themeFontSize(16, this.theme), family: this.theme.fontFamily })
        .optionFontColor($r('app.color.content_primary')).selectedOptionFontColor(this.theme.accent)
        .optionBgColor(this.theme.surface).selectedOptionBgColor(this.theme.accentSurface)
        .menuBackgroundColor(this.theme.surface)
        .fontColor($r('app.color.content_primary')).backgroundColor(Color.Transparent).layoutWeight(1)
        .accessibilityText('应用字体').onSelect((index: number): void => {
          this.update((next: AppSettings): void => { next.fontFamily = THEME_FONTS[index]; });
        })
    }.width('100%').padding(16).borderRadius(24).backgroundColor(this.theme.surface)
    this.sectionTitle('文本缩放', $r('app.media.theme_type'))
    SingleChoiceControl({
      labels: ['跟随系统', '自定义'], selectedIndex: this.settings.followSystemFontScale ? 0 : 1,
      accessibilityLabel: '文本缩放',
      onChange: (index: number): void => {
        this.update((next: AppSettings): void => { next.followSystemFontScale = index === 0; });
      }
    })
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Text('Aa').fontSize(themeFontSize(20, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_primary')).layoutWeight(1)
        Text(this.settings.followSystemFontScale ? '跟随系统' : `${this.scaleDraft}%`)
          .fontSize(themeFontSize(12, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_secondary')).padding(6).borderRadius(12).backgroundColor(this.theme.inset)
      }.width('100%')
      Text('应用内的文字将以这个大小显示').fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
        .fontColor($r('app.color.content_secondary')).width('100%')
      if (!this.settings.followSystemFontScale) {
        Slider({ value: this.scaleDraft, min: MIN_CUSTOM_FONT_SCALE * 100, max: MAX_CUSTOM_FONT_SCALE * 100, step: 5 })
          .id('theme-font-scale').width('100%').showSteps(true).showTips(true).selectedColor(this.theme.accent)
          .trackColor(this.theme.muted).blockColor(this.theme.accent)
          .accessibilityText('自定义文字大小，85% 至 200%')
          .onChange((value: number, mode: SliderChangeMode): void => {
            this.scaleDraft = value;
            if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
              this.update((next: AppSettings): void => { next.customFontScale = value / 100; });
            }
          })
      }
    }.width('100%').padding(16).borderRadius(24).backgroundColor(this.theme.surface)
  }

  @Builder
  private pageHeader() {
    SecondaryPageHeader({ title: '主题', contentPadding: this.contentPadding, onBack: this.onBack })
  }

  @Builder
  private content() {
    Scroll() {
      Column({ space: 12 }) {
        Column() { ThemePreview({ palette: this.theme }) }
          .width('100%').padding(24).borderRadius(28).backgroundColor(this.theme.surface)
          .accessibilityText('当前主题预览')
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor($r('app.color.status_error')).width('100%')
        }
        this.modes()
        this.colors()
        this.animationSection()
        this.typography()
      }.width('100%').constraintSize({ maxWidth: 640 })
        .padding({ top: this.headerInset, bottom: 32, left: this.contentPadding, right: this.contentPadding })
    }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
  }

  build() {
    FadingScrollLayout({
      topInset: $headerInset,
      header: (): void => { this.pageHeader(); },
      content: (): void => { this.content(); }
    }).onAreaChange((_old: Area, area: Area): void => {
      this.contentPadding = resolveResponsiveMetrics(resolveContentWidth(area.width)).pagePadding;
    })
  }
}
