import { CONTROL_HEIGHT, DETAIL_CARD_RADIUS, BODY_FONT_SIZE } from '../constants/UiConstants';
import { resourceInputError } from '../utils/DiagnosticsUtils';
import { revealTransition } from '../utils/AnimationUtils';

@CustomDialog
export struct ResourceInputDialog {
  controller?: CustomDialogController;
  title: string = '';
  initialInput: string = '';
  interval: boolean = false;
  onSubmit: (value: string) => Promise<void> = async (): Promise<void> => {};
  @State input: string = '';
  @State errorMessage: string = '';
  @State saving: boolean = false;

  aboutToAppear(): void { this.input = this.initialInput; }

  private async submit(): Promise<void> {
    this.errorMessage = resourceInputError(this.input, this.interval);
    if (this.errorMessage.length > 0 || this.saving) { return; }
    this.saving = true;
    try {
      await this.onSubmit(this.input.trim());
      this.controller?.close();
    } catch (error) {
      this.errorMessage = (error as Error).message || '保存失败，请重试';
    } finally { this.saving = false; }
  }

  build() {
    Column({ space: 20 }) {
      Text(this.title).fontSize(22).fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary'))
      Column({ space: 8 }) {
        Text(this.interval ? '更新间隔（小时）' : '下载地址').fontSize(14)
          .fontColor($r('app.color.content_secondary')).width('100%')
        TextArea({ text: this.input, placeholder: this.interval ? '1–720' : 'https://' })
          .id('resource-input').height(this.interval ? 64 : 128).fontSize(BODY_FONT_SIZE)
          .type(this.interval ? TextAreaType.NUMBER : TextAreaType.NORMAL)
          .fontColor($r('app.color.content_primary')).placeholderColor($r('app.color.content_secondary'))
          .backgroundColor($r('app.color.app_background')).borderRadius(20).padding(16)
          .enabled(!this.saving).accessibilityText(this.interval ? '自动更新间隔，1 至 720 小时' : `${this.title} 下载地址`)
          .onChange((value: string): void => { this.input = value; })
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage).fontSize(14).fontColor($r('app.color.status_error')).width('100%')
            .transition(revealTransition())
        }
      }.width('100%')
      Row({ space: 12 }) {
        Button('取消').height(CONTROL_HEIGHT).layoutWeight(1).borderRadius(24)
          .fontColor($r('app.color.content_primary')).backgroundColor($r('app.color.surface_muted'))
          .enabled(!this.saving).onClick((): void => { this.controller?.close(); })
        Button(this.saving ? '保存中…' : '提交').height(CONTROL_HEIGHT).layoutWeight(1).borderRadius(24)
          .fontColor($r('app.color.accent_foreground')).backgroundColor($r('app.color.action_primary'))
          .enabled(!this.saving).onClick((): void => { this.submit(); })
      }.width('100%')
    }
    .width('90%').constraintSize({ maxWidth: 440 }).padding(24).borderRadius(DETAIL_CARD_RADIUS + 8)
    .backgroundColor($r('app.color.card_background'))
  }
}
