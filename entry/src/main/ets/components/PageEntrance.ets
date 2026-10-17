import { NavigationTransition } from '../model/SettingsModels';
import { selectionAnimation } from '../utils/AnimationUtils';

/** 包装页面入场效果；initialOffset 由切换方向决定，并遵循系统减少动画偏好。 */
@Component
export struct PageEntrance {
  @Prop effect: NavigationTransition = NavigationTransition.FADE;
  @Prop initialOffset: number = 24;
  @State contentOpacity: number = 0;
  @State contentOffset: number = 0;
  @BuilderParam content: () => void;
  private animationOptions: AnimateParam = selectionAnimation();

  aboutToAppear(): void {
    if (this.animationOptions.duration === 0) {
      this.contentOpacity = 1;
    } else if (this.effect === NavigationTransition.SLIDE) {
      this.contentOffset = this.initialOffset;
    }
  }

  build() {
    Column() { this.content() }
      .width('100%').height('100%')
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
