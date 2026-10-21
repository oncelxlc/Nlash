import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME } from '../utils/ThemeUtils';
import { CONTROL_HEIGHT } from '../constants/UiConstants';

@Component
export struct HeaderIconButton {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop icon: Resource = $r('app.media.action_search');
  @Prop label: string = '';
  @Prop available: boolean = true;
  @Prop busy: boolean = false;
  onActivate: () => void = (): void => {};

  build() {
    Button({ type: ButtonType.Circle }) {
      if (this.busy) {
        LoadingProgress().width(24).height(24).color($r('app.color.content_primary'))
      } else {
        Image(this.icon).width(24).height(24).fillColor($r('app.color.content_primary')).accessibilityLevel('no')
      }
    }
    .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).padding(0)
    .backgroundColor(this.theme.surface).enabled(this.available && !this.busy)
    .opacity(this.available ? 1 : 0.4).accessibilityText(this.busy ? `${this.label}，处理中` : this.label)
    .onClick((): void => { this.onActivate(); })
  }
}
