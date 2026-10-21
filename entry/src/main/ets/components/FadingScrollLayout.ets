import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME } from '../utils/ThemeUtils';
/** 固定标题覆盖滚动内容；按实际标题高度留白，渐变层不拦截手势。 */
@Component
export struct FadingScrollLayout {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop surface: ResourceColor | undefined = undefined;
  @Prop transparentSurface: ResourceColor | undefined = undefined;
  @Prop @Watch('updateInset') gap: number = 16;
  @Link topInset: number;
  @BuilderParam header: () => void;
  @BuilderParam content: () => void;
  private headerHeight: number = 0;

  private updateInset(): void {
    this.topInset = this.headerHeight + this.gap;
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // List 的初始偏移必须在首次布局前确定，否则首项会停在标题下面。
      if (this.topInset > 0) {
        this.content()
      }
      Row()
        .width('100%').height(this.topInset)
        .linearGradient({
          direction: GradientDirection.Bottom,
          colors: [[this.surface ?? this.theme.background, 0],
            [this.surface ?? this.theme.background, this.headerHeight / Math.max(1, this.topInset)],
            [this.transparentSurface ?? this.theme.transparentBackground, 1]]
        })
        .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      Column() { this.header() }
        .id('page-header').width('100%')
        .onAreaChange((_old: Area, area: Area): void => {
          this.headerHeight = Number(area.height);
          this.updateInset();
        })
    }
    .width('100%').height('100%').backgroundColor(this.surface ?? this.theme.background)
  }
}
