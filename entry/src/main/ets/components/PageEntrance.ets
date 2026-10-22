import { NavigationTransition } from '../model/SettingsModels';
import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME } from '../utils/ThemeUtils';
import { selectionAnimation } from '../utils/AnimationUtils';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 用上一帧覆盖新内容做转场，避免先清空页面再淡入；快照只在动画期间存活。 */
@Component
export struct PageEntrance {
  @StorageProp('appTheme') @Watch('onThemeChange') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop effect: NavigationTransition = NavigationTransition.FADE;
  @Prop @Watch('onPageChange') pageKey: number = 0;
  @Prop initialOffset: number = 24;
  @State previousFrame: image.PixelMap | undefined = undefined;
  @State frameOpacity: number = 1;
  @State frameOffset: number = 0;
  @State frameWidth: number = 0;
  @State frameHeight: number = 0;
  @BuilderParam content: () => void;
  private generation: number = 0;

  aboutToDisappear(): void {
    this.generation += 1;
    this.releaseFrame(this.previousFrame);
    this.previousFrame = undefined;
  }

  private onPageChange(): void { this.animateChange(this.effect === NavigationTransition.SLIDE); }

  private onThemeChange(): void { this.animateChange(false); }

  private releaseFrame(frame: image.PixelMap | undefined): void {
    frame?.release().catch((error: Error): void => {
      hilog.warn(0x0000, 'NlashTheme', 'Cannot release transition snapshot: %{public}s', error.message);
    });
  }

  private animateChange(slide: boolean): void {
    const options = selectionAnimation(slide ? 300 : 450);
    const previous = this.previousFrame;
    const generation = ++this.generation;
    if (options.duration === 0) {
      this.previousFrame = undefined;
      this.releaseFrame(previous);
      return;
    }
    let frame: image.PixelMap;
    try {
      // getSync 读取已渲染的上一帧，包含尚未结束的过渡，连续切换也不会跳回旧画面。
      frame = this.getUIContext().getComponentSnapshot().getSync('page-transition-root');
    } catch (error) {
      this.previousFrame = undefined;
      this.releaseFrame(previous);
      hilog.warn(0x0000, 'NlashTheme', 'Cannot capture transition snapshot: %{public}s', String(error));
      return;
    }
    this.getUIContext().animateTo({ duration: 0 }, (): void => {
      // 快照包含扩展安全区，按实际像素尺寸展示，不能按布局高度再次缩放。
      const size = frame.getImageInfoSync().size;
      this.frameWidth = this.getUIContext().px2vp(size.width);
      this.frameHeight = this.getUIContext().px2vp(size.height);
      this.previousFrame = frame;
      this.frameOpacity = 1;
      this.frameOffset = 0;
    });
    this.releaseFrame(previous);
    options.onFinish = (): void => {
      if (generation !== this.generation) { return; }
      this.previousFrame = undefined;
      this.releaseFrame(frame);
    };
    this.getUIContext().animateTo(options, (): void => {
      this.frameOpacity = 0;
      this.frameOffset = slide ? -this.initialOffset : 0;
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
      if (this.previousFrame !== undefined) {
        Image(this.previousFrame).width(this.frameWidth).height(this.frameHeight).objectFit(ImageFit.Fill).syncLoad(true)
          .opacity(this.frameOpacity).translate({ x: this.frameOffset })
          .hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      }
    }.id('page-transition-root').width('100%').height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
