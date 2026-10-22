import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { coreClient } from '../services/CoreClient';
import { resolveContentWidth, resolveResponsiveMetrics } from '../utils/ResponsiveUtils';
import { BODY_FONT_SIZE, CAPTION_FONT_SIZE, CARD_RADIUS } from '../constants/UiConstants';
import { FadingScrollLayout } from '../components/FadingScrollLayout';
import { SecondaryPageHeader } from '../components/SecondaryPageHeader';

@Component
export struct AboutPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  onBack: () => void = (): void => {};
  @State coreVersion: string = '--';
  @State headerInset: number = 0;
  @State contentPadding: number = 16;

  aboutToAppear(): void {
    try { this.coreVersion = coreClient.getVersion(); }
    catch (_error) { this.coreVersion = 'Core 不可用'; }
  }

  @Builder
  private pageHeader() {
    SecondaryPageHeader({ title: '关于', contentPadding: this.contentPadding, onBack: this.onBack })
  }

  @Builder
  private content() {
    Scroll() {
      Column() {
        Column({ space: 12 }) {
          Text('关于 Nlash').fontSize(themeFontSize(18, this.theme)).fontFamily(this.theme.fontFamily)
            .fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary')).width('100%')
          Text(`1.0.0 · ${this.coreVersion}`).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme))
            .fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).width('100%')
          Divider().color(this.theme.divider)
          Text('Clash.Meta 8380d0e7462f').fontSize(themeFontSize(BODY_FONT_SIZE, this.theme))
            .fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_primary')).width('100%')
          Text('配置与订阅保存在应用沙箱中。').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme))
            .fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).width('100%')
        }.alignItems(HorizontalAlign.Start).width('100%').padding(16)
          .borderRadius(CARD_RADIUS).backgroundColor(this.theme.surface)
      }.width('100%').constraintSize({ maxWidth: 640 })
        .padding({ top: this.headerInset, bottom: 32, left: this.contentPadding, right: this.contentPadding })
    }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
  }

  build() {
    FadingScrollLayout({ topInset: $headerInset,
      header: (): void => { this.pageHeader(); }, content: (): void => { this.content(); } })
      .onAreaChange((_old: Area, area: Area): void => {
        this.contentPadding = resolveResponsiveMetrics(resolveContentWidth(area.width)).pagePadding;
      })
  }
}
