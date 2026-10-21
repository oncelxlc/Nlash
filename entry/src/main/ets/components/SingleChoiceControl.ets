import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { CAPTION_FONT_SIZE, CONTROL_HEIGHT } from '../constants/UiConstants';
import { selectionAnimation } from '../utils/AnimationUtils';

/** 受控单选组件，选中项由父级更新；横向滚动用于容纳较多或较长选项。 */
@Component
export struct SingleChoiceControl {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop labels: string[] = [];
  @Prop selectedIndex: number = 0;
  @Prop isEnabled: boolean = true;
  @Prop compact: boolean = false;
  @Prop scrollable: boolean = false;
  @Prop textOnly: boolean = false;
  @Prop accessibilityLabel: string = '';
  onChange: (index: number) => void = (): void => {};
  private animationOptions: AnimateParam = selectionAnimation();

  private choiceHeight(): number {
    const scale = this.theme.fontScale || this.getUIContext().fp2px(1) / this.getUIContext().vp2px(1);
    return Math.max(this.compact ? 40 : CONTROL_HEIGHT, (this.compact ? CAPTION_FONT_SIZE : 14) * scale * 2.4 + 8);
  }

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
            .fontSize(themeFontSize(this.compact ? CAPTION_FONT_SIZE : 14, this.theme)).fontFamily(this.theme.fontFamily)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(this.selectedIndex === index ? this.theme.onAccent :
              (this.textOnly ? $r('app.color.content_secondary') : $r('app.color.content_primary')))
        }
        .height(this.choiceHeight())
        .constraintSize({ minWidth: CONTROL_HEIGHT })
        .responseRegion({ x: 0, y: this.compact ? -4 : 0, width: '100%', height: Math.max(CONTROL_HEIGHT, this.choiceHeight()) })
        .layoutWeight(this.scrollable ? 0 : 1)
        .padding(0)
        .borderRadius(8)
        .backgroundColor(this.selectedIndex === index ? this.theme.accent : this.theme.muted)
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
    .height(this.choiceHeight())
  }

  build() {
    if (this.scrollable) {
      Scroll() { this.choices() }
        .width('100%').height(this.choiceHeight())
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .align(Alignment.Start)
    } else {
      this.choices()
    }
  }
}
