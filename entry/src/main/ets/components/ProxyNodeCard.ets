import { BODY_FONT_SIZE, CAPTION_FONT_SIZE, CONTROL_HEIGHT } from '../constants/UiConstants';
import { ProxyNodeSnapshot } from '../model/RuntimeModels';
import { selectionAnimation } from '../utils/AnimationUtils';
import { proxyDelayLabel } from '../utils/RuntimeUtils';

/** 节点选择与延迟测试分开触发，业务状态由父页面提供。 */
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
    Column({ space: 4 }) {
      Row({ space: 4 }) {
        Text(this.node.name)
          .fontSize(BODY_FONT_SIZE).fontColor($r('app.color.content_primary'))
          .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.selected) {
          Image($r('app.media.action_check')).width(24).height(24).padding(4)
            .fillColor($r('app.color.accent_foreground')).borderRadius(12)
            .backgroundColor($r('app.color.action_primary')).accessibilityLevel('no')
        }
      }
      .width('100%').constraintSize({ minHeight: 32 }).alignItems(VerticalAlign.Top)
      Row({ space: 4 }) {
        Text(this.node.type).fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
          .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        Row() {
          Button({ type: ButtonType.Normal }) {
            if (this.testing) {
              LoadingProgress().width(18).height(18).color($r('app.color.action_primary'))
            } else if (!this.node.tested) {
              Image($r('app.media.action_bolt')).width(18).height(18)
                .fillColor($r('app.color.action_primary')).accessibilityLevel('no')
            } else {
              Text(proxyDelayLabel(this.node, false)).fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
                .fontColor(this.node.alive && this.node.delay > 0 ?
                  $r('app.color.proxy_delay_success') : $r('app.color.status_error'))
            }
          }
          .constraintSize({ minWidth: CONTROL_HEIGHT, minHeight: CONTROL_HEIGHT / 2.4 })
          .padding({ left: 4, right: 4 })
          .borderRadius(16)
          .backgroundColor(Color.Transparent)
          .enabled(this.canTest && !this.testing)
          .accessibilityText(`测试 ${this.node.name} 延迟，${proxyDelayLabel(this.node, this.testing)}`)
          .onClick((): void => { this.onTest(); })
        }
        .focusable(false).accessibilityLevel('no')
        // 测速禁用时仍消费点击，避免误选节点。
        .onClick((): void => {})
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding({ left: 12, right: 8, top: 12, bottom: 4 }).borderRadius(24)
    .backgroundColor($r('app.color.proxy_node_background'))
    .animation(this.animationOptions)
    .focusable(this.canSelect).accessibilityRole(AccessibilityRoleType.BUTTON)
    .accessibilityText(`${this.node.name}，${this.node.type}，${this.node.udp ? 'UDP / TCP' : 'TCP'}` +
      `${this.selected ? '，已选择' : ''}${this.canSelect ? '' : '，自动选择组'}`)
    .accessibilitySelected(this.selected)
    .onClick((): void => { if (this.canSelect && !this.selected) { this.onSelect(); } })
  }
}
