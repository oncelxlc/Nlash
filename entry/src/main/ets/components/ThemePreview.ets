import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME } from '../utils/ThemeUtils';

/** 用实际主题色绘制缩略图，所有外观选项共用即时预览。 */
@Component
export struct ThemePreview {
  @Prop palette: AppTheme = DEFAULT_APP_THEME;
  @Prop miniature: boolean = false;

  private scaled(value: number): number { return this.miniature ? value * 0.24 : value; }

  @Builder
  private line(width: Length, accent: boolean = false) {
    Row().width(width).height(this.scaled(5)).borderRadius(this.scaled(3))
      .backgroundColor(accent ? this.palette.accent : (this.palette.dark ? '#93939D' : '#A1A1AA'))
  }

  @Builder
  private card() {
    Column({ space: this.scaled(8) }) {
      this.line('40%')
      this.line('70%', true)
      this.line('50%')
    }.alignItems(HorizontalAlign.Start).padding(this.scaled(10)).width('100%')
      .backgroundColor(this.palette.surface).borderRadius(this.scaled(12))
  }

  build() {
    Column({ space: this.scaled(7) }) {
      Row() {
        this.line('45%')
        Blank()
        Row().borderRadius(100).width(this.scaled(9)).height(this.scaled(9)).backgroundColor(this.palette.muted)
      }.width('100%').margin({ bottom: this.scaled(4) })
      Row({ space: this.scaled(10) }) {
        Column({ space: this.scaled(9) }) {
          this.line('80%')
          this.line('55%')
          this.line('65%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Row().borderRadius(100).width(this.scaled(33)).height(this.scaled(33)).backgroundColor(this.palette.accent)
      }.width('100%').padding(this.scaled(10)).borderRadius(this.scaled(12))
        .backgroundColor(this.palette.accentSurface)
      Row({ space: this.scaled(6) }) {
        Column({ space: this.scaled(9) }) {
          this.line('65%')
          this.line('90%', true)
        }.padding(this.scaled(9)).layoutWeight(1).borderRadius(this.scaled(12)).backgroundColor(this.palette.surface)
        Column({ space: this.scaled(9) }) {
          this.line('60%')
          this.line('90%', true)
        }.padding(this.scaled(9)).layoutWeight(1).borderRadius(this.scaled(12)).backgroundColor(this.palette.surface)
      }.width('100%')
      Row({ space: this.scaled(5) }) {
        ForEach([0, 1, 2], (index: number) => {
          Row().height(this.scaled(12)).layoutWeight(1).borderRadius(this.scaled(6))
            .backgroundColor(index === 0 ? this.palette.accent : this.palette.muted)
        })
      }.width('100%').padding(this.scaled(8)).borderRadius(this.scaled(12)).backgroundColor(this.palette.surface)
      this.card()
      Row({ space: this.scaled(18) }) {
        ForEach([0, 1, 2, 3], (index: number) => {
          Row().borderRadius(100).width(this.scaled(8)).height(this.scaled(8)).backgroundColor(index === 0 ? this.palette.accent : this.palette.muted)
        })
      }.justifyContent(FlexAlign.Center).width('100%').padding(this.scaled(8))
        .borderRadius(this.scaled(12)).backgroundColor(this.palette.surface)
    }
    .width(this.scaled(152)).padding(this.scaled(10)).borderRadius(this.scaled(23))
    .backgroundColor(this.palette.background)
    .border({ width: this.miniature ? 1 : 3, color: this.palette.muted })
    .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
  }
}
