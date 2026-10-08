import { CAPTION_FONT_SIZE, CONTROL_HEIGHT } from '../constants/UiConstants';

@Component
export struct SingleChoiceControl {
  @Prop labels: string[] = [];
  @Prop selectedIndex: number = 0;
  @Prop isEnabled: boolean = true;
  @Prop compact: boolean = false;
  @Prop scrollable: boolean = false;
  @Prop accessibilityLabel: string = '';
  onChange: (index: number) => void = (): void => {};

  @Builder
  private choices() {
    Row() {
      ForEach(this.labels, (label: string, index: number) => {
        Button({ type: ButtonType.Normal }) {
          Text(label)
            .width(this.scrollable ? undefined : '100%')
            .height(this.compact ? 32 : 40)
            .constraintSize({ minWidth: CONTROL_HEIGHT })
            .padding({ left: this.compact ? 4 : 12, right: this.compact ? 4 : 12 })
            .fontSize(this.compact ? CAPTION_FONT_SIZE : 14)
            .fontWeight(this.selectedIndex === index ? FontWeight.Medium : FontWeight.Normal)
            .textAlign(TextAlign.Center)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.selectedIndex === index ?
              $r('app.color.accent_foreground') : $r('app.color.content_primary'))
            .backgroundColor(this.selectedIndex === index ?
              $r('app.color.action_primary') : $r('app.color.card_background'))
            .border({
              width: { top: 1, bottom: 1, left: index === 0 ? 1 : 0, right: 1 },
              color: this.selectedIndex === index ? $r('app.color.action_primary') : $r('app.color.control_border')
            })
            .borderRadius({
              topLeft: index === 0 ? 6 : 0, bottomLeft: index === 0 ? 6 : 0,
              topRight: index === this.labels.length - 1 ? 6 : 0,
              bottomRight: index === this.labels.length - 1 ? 6 : 0
            })
        }
        // The flat strip retains a full 48vp touch target.
        .height(CONTROL_HEIGHT)
        .constraintSize({ minWidth: CONTROL_HEIGHT })
        .layoutWeight(this.scrollable ? 0 : 1)
        .padding(0)
        .borderRadius(6)
        .backgroundColor(Color.Transparent)
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
    .height(CONTROL_HEIGHT)
  }

  build() {
    if (this.scrollable) {
      Scroll() { this.choices() }
        .width('100%').height(CONTROL_HEIGHT)
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
    } else {
      this.choices()
    }
  }
}
