import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, normalizeThemeColor, themeFontSize } from '../utils/ThemeUtils';
import { CONTROL_HEIGHT } from '../constants/UiConstants';

@CustomDialog
export struct ThemeColorDialog {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  controller?: CustomDialogController;
  initialColor: string = '#2F80FF';
  onSubmit: (color: string) => Promise<void> = async (): Promise<void> => {};
  @State input: string = '';
  @State errorMessage: string = '';
  @State saving: boolean = false;

  aboutToAppear(): void { this.input = this.initialColor; }

  private async submit(): Promise<void> {
    const color = normalizeThemeColor(this.input);
    if (color === undefined) {
      this.errorMessage = '请输入 #RRGGBB 格式的六位颜色值';
      return;
    }
    if (this.saving) { return; }
    this.saving = true;
    try {
      await this.onSubmit(color);
      this.controller?.close();
    } catch (error) {
      this.errorMessage = (error as Error).message || '保存失败，请重试';
    } finally { this.saving = false; }
  }

  build() {
    Column({ space: 16 }) {
      Text('自定义主题色').fontSize(themeFontSize(22, this.theme)).fontFamily(this.theme.fontFamily)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary'))
      Row({ space: 12 }) {
        Row().borderRadius(100).width(36).height(36).backgroundColor(normalizeThemeColor(this.input) ?? this.theme.muted).accessibilityLevel('no')
        TextInput({ text: this.input, placeholder: '#2F80FF' }).id('theme-custom-color-input')
          .layoutWeight(1).constraintSize({ minHeight: CONTROL_HEIGHT }).maxLength(7)
          .fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
          .placeholderFont({ size: themeFontSize(16, this.theme), family: this.theme.fontFamily })
          .fontColor($r('app.color.content_primary')).backgroundColor(this.theme.inset)
          .accessibilityText('自定义主题色，六位十六进制颜色').enabled(!this.saving)
          .onChange((value: string): void => { this.input = value; this.errorMessage = ''; })
      }.width('100%')
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.status_error')).width('100%')
      }
      Row({ space: 12 }) {
        Button('取消').layoutWeight(1).constraintSize({ minHeight: CONTROL_HEIGHT })
          .fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_primary')).backgroundColor(this.theme.muted).enabled(!this.saving)
          .onClick((): void => { this.controller?.close(); })
        Button(this.saving ? '保存中…' : '保存').id('theme-custom-color-save').layoutWeight(1)
          .constraintSize({ minHeight: CONTROL_HEIGHT }).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor(this.theme.onAccent).backgroundColor(this.theme.accent).enabled(!this.saving)
          .onClick((): void => { this.submit(); })
      }.width('100%')
    }.width('90%').constraintSize({ maxWidth: 440 }).padding(24).borderRadius(28).backgroundColor(this.theme.surface)
  }
}
