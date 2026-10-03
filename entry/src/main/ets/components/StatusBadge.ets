import { CAPTION_FONT_SIZE } from '../constants/UiConstants';

@Component
export struct StatusBadge {
  @Prop text: ResourceStr = '';
  @Prop active: boolean = false;
  @Prop error: boolean = false;

  build() {
    Text(this.text)
      .fontSize(CAPTION_FONT_SIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.error ? $r('app.color.status_error') :
        (this.active ? $r('app.color.status_success') : $r('app.color.content_secondary')))
      .backgroundColor(this.error ? $r('app.color.status_error_surface') :
        (this.active ? $r('app.color.status_success_surface') : $r('app.color.surface_muted')))
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(6)
  }
}
