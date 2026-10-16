import { CAPTION_FONT_SIZE, CONTROL_HEIGHT } from '../constants/UiConstants';
import { selectionAnimation } from '../utils/AnimationUtils';

@Component
export struct SingleChoiceControl {
  @Prop labels: string[] = [];
  @Prop selectedIndex: number = 0;
  @Prop isEnabled: boolean = true;
  @Prop compact: boolean = false;
  @Prop scrollable: boolean = false;
  @Prop textOnly: boolean = false;
  @Prop accessibilityLabel: string = '';
  onChange: (index: number) => void = (): void => {};
  private animationOptions: AnimateParam = selectionAnimation();

  @Builder
  private choices() {
    Row({ space: 8 }) {
      ForEach(this.labels, (label: string, index: number) => {
        Button({ type: ButtonType.Normal }) {
          Text(label)
            .width(this.scrollable ? undefined : '100%')
            .height('100%')
            .constraintSize({ minWidth: CONTROL_HEIGHT })
            .padding({ left: this.compact ? 4 : 12, right: this.compact ? 4 : 12 })
            .fontSize(this.compact ? CAPTION_FONT_SIZE : 14)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.selectedIndex === index ? $r('app.color.accent_foreground') :
              (this.textOnly ? $r('app.color.content_secondary') : $r('app.color.content_primary')))
        }
        .height(this.compact ? 40 : CONTROL_HEIGHT)
        .constraintSize({ minWidth: CONTROL_HEIGHT })
        .responseRegion({ x: 0, y: this.compact ? -4 : 0, width: '100%', height: CONTROL_HEIGHT })
        .layoutWeight(this.scrollable ? 0 : 1)
        .padding(0)
        .borderRadius(8)
        .backgroundColor(this.selectedIndex === index ? $r('app.color.action_primary') : $r('app.color.surface_muted'))
        .animation(this.animationOptions)
        .enabled(this.isEnabled)
        .accessibilityText(this.accessibilityLabel.length > 0 ? `${this.accessibilityLabel}：${label}` : label)
        .accessibilitySelected(this.selectedIndex === index)
        .onClick((): void => {
          if (this.isEnabled && this.selectedIndex !== index) {
            this.onChange(index);
          }
        })
      }, (label: string, index: number): string => `${index}:${label}`)
    }
    .width(this.scrollable ? undefined : '100%')
    .height(this.compact ? 40 : CONTROL_HEIGHT)
  }

  build() {
    if (this.scrollable) {
      Scroll() { this.choices() }
        .width('100%').height(this.compact ? 40 : CONTROL_HEIGHT)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
    } else {
      this.choices()
    }
  }
}
