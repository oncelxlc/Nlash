import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { CONTROL_HEIGHT, DETAIL_CARD_RADIUS, BODY_FONT_SIZE } from '../constants/UiConstants';

@CustomDialog
export struct GeneralInputDialog {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  controller?: CustomDialogController;
  title: string = '';
  hint: string = '';
  initialInput: string = '';
  multiline: boolean = false;
  secret: boolean = false;
  numeric: boolean = false;
  onSubmit: (value: string) => Promise<void> = async (): Promise<void> => {};
  @State input: string = '';
  @State saving: boolean = false;
  @State errorMessage: string = '';

  aboutToAppear(): void { this.input = this.initialInput; }

  private async submit(): Promise<void> {
    if (this.saving) { return; }
    this.saving = true;
    this.errorMessage = '';
    try {
      await this.onSubmit(this.input);
      this.controller?.close();
    } catch (error) {
      this.errorMessage = (error as Error).message || '保存失败，请重试';
    } finally { this.saving = false; }
  }

  build() {
    Column({ space: 16 }) {
      Text(this.title).fontSize(themeFontSize(22, this.theme)).fontFamily(this.theme.fontFamily)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary')).width('100%')
      Text(this.hint).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
        .fontColor($r('app.color.content_secondary')).width('100%')
      if (this.multiline) {
        TextArea({ text: this.input, placeholder: 'example.com = 1.2.3.4' })
          .id('general-hosts-input').height(200).fontSize(themeFontSize(BODY_FONT_SIZE, this.theme))
          .placeholderFont({ size: themeFontSize(BODY_FONT_SIZE, this.theme), family: this.theme.fontFamily })
          .fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_primary'))
          .placeholderColor($r('app.color.content_secondary')).backgroundColor(this.theme.background)
          .borderRadius(16).padding(16).maxLength(10000).enabled(!this.saving).accessibilityText(this.title)
          .onChange((value: string): void => { this.input = value; })
      } else {
        TextInput({ text: this.input })
          .id('general-input').type(this.secret ? InputType.Password : (this.numeric ? InputType.Number : InputType.Normal))
          .height(CONTROL_HEIGHT).fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_primary')).backgroundColor(this.theme.background).borderRadius(16)
          .maxLength(this.secret ? 128 : 2048).enabled(!this.saving).accessibilityText(this.title)
          .onChange((value: string): void => { this.input = value; })
      }
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.status_error')).width('100%')
      }
      Row({ space: 12 }) {
        Button('取消').constraintSize({ minHeight: CONTROL_HEIGHT }).layoutWeight(1)
          .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_primary')).backgroundColor(this.theme.muted)
          .enabled(!this.saving).onClick((): void => { this.controller?.close(); })
        Button(this.saving ? '保存中…' : '保存').constraintSize({ minHeight: CONTROL_HEIGHT }).layoutWeight(1)
          .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor(this.theme.onAccent).backgroundColor(this.theme.accent)
          .enabled(!this.saving).onClick((): void => { this.submit(); })
      }.width('100%')
    }.width('100%').constraintSize({ maxWidth: 520 }).padding(24).borderRadius(DETAIL_CARD_RADIUS)
      .backgroundColor(this.theme.surface)
  }
}
