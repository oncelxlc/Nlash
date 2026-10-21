import { NavigationTransition } from '../model/SettingsModels';
import { selectionAnimation } from '../utils/AnimationUtils';

/** 包装页面入场效果；initialOffset 由切换方向决定，并遵循系统减少动画偏好。 */
@Component
export struct PageEntrance {
  @Prop effect: NavigationTransition = NavigationTransition.FADE;
  @Prop initialOffset: number = 24;
  @State contentOpacity: number = 0;
  @State contentOffset: number = 0;
  @State entering: boolean = true;
  @BuilderParam content: () => void;
  private animationOptions: AnimateParam = selectionAnimation();

  aboutToAppear(): void {
    this.animationOptions.onFinish = (): void => { this.entering = false; };
    if (this.animationOptions.duration === 0) {
      this.contentOpacity = 1;
      this.entering = false;
    } else if (this.effect === NavigationTransition.SLIDE) {
      this.contentOffset = this.initialOffset;
    }
  }

  build() {
    Column() { this.content() }
      .width('100%').height('100%')
      // 入场时先合成整页，避免透明度逐层叠加透出吸顶组头下的节点。
      .renderGroup(this.entering)
      .opacity(this.contentOpacity)
      .translate({ x: this.contentOffset })
      .onAppear((): void => {
        this.getUIContext().animateTo(this.animationOptions, (): void => {
          this.contentOpacity = 1;
          this.contentOffset = 0;
        });
      })
  }
}
