import { BODY_FONT_SIZE, CAPTION_FONT_SIZE, CARD_RADIUS, CONTROL_HEIGHT } from '../constants/UiConstants';
import { ProxyNodeSnapshot } from '../model/RuntimeModels';
import { selectionAnimation } from '../utils/AnimationUtils';
import { proxyDelayLabel } from '../utils/RuntimeUtils';

@Component
export struct ProxyNodeCard {
  @Prop node: ProxyNodeSnapshot = { name: '', type: '', alive: false, tested: false, delay: 0, udp: false };
  @Prop selected: boolean = false;
  @Prop canSelect: boolean = false;
  @Prop testing: boolean = false;
  @Prop canTest: boolean = false;
  onSelect: () => void = (): void => {};
  onTest: () => void = (): void => {};
  private animationOptions: AnimateParam = selectionAnimation();

  build() {
    Row({ space: 4 }) {
      Column({ space: 4 }) {
        Text(this.node.name)
          .constraintSize({ minHeight: CONTROL_HEIGHT })
          .fontSize(BODY_FONT_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .focusable(this.canSelect)
          .accessibilityRole(AccessibilityRoleType.BUTTON)
          .stateStyles({ pressed: { .opacity(0.6) } })
          .enabled(this.canSelect)
          .accessibilityText(`${this.node.name}${this.selected ? '，已选择' : ''}`)
          .accessibilitySelected(this.selected)
          .onClick((): void => { if (this.canSelect && !this.selected) { this.onSelect(); } })
        Text(`${this.node.type} · ${this.node.udp ? 'UDP / TCP' : 'TCP'}`)
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(proxyDelayLabel(this.node, this.testing))
        .constraintSize({ minWidth: CONTROL_HEIGHT, minHeight: CONTROL_HEIGHT })
        .textAlign(TextAlign.End)
        .fontSize(CAPTION_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.testing || !this.node.tested ? $r('app.color.content_secondary') :
          (this.node.alive ? $r('app.color.status_success') : $r('app.color.status_error')))
        .focusable(true)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .stateStyles({ pressed: { .opacity(0.6) } })
        .enabled(this.canTest && !this.testing)
        .accessibilityText(`测试 ${this.node.name} 延迟，${proxyDelayLabel(this.node, this.testing)}`)
        .onClick((): void => { this.onTest(); })
    }
    .width('100%')
    .padding(8)
    .borderRadius(CARD_RADIUS)
    .backgroundColor(this.selected ? $r('app.color.nav_selected_background') : $r('app.color.card_background'))
    .animation(this.animationOptions)
  }
}
