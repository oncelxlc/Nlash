import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { CONTROL_HEIGHT } from '../constants/UiConstants';

/** 原生确认框不采用应用的强调色和自定义字号，统一使用同一套主题文本。 */
@CustomDialog
export struct ThemeAlertDialog {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  controller?: CustomDialogController;
  title: string = '';
  message: string = '';
  confirmLabel: string = '确定';
  cancelLabel: string = '取消';
  destructive: boolean = false;
  onConfirm: () => void = (): void => {};
  onCancel: () => void = (): void => {};

  @Builder
  private action(label: string, confirm: boolean) {
    Button({ type: ButtonType.Normal }) {
      Text(label).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
        .fontWeight(FontWeight.Medium).textAlign(TextAlign.Center).maxLines(2)
        .fontColor(confirm ? (this.destructive ? $r('app.color.status_error') : this.theme.onAccent) :
          $r('app.color.content_primary'))
    }.layoutWeight(1).constraintSize({ minHeight: CONTROL_HEIGHT }).padding(12).borderRadius(24)
      .backgroundColor(confirm ? (this.destructive ? $r('app.color.status_error_surface') : this.theme.accent) :
        this.theme.muted)
      .onClick((): void => {
        this.controller?.close();
        if (confirm) { this.onConfirm(); } else { this.onCancel(); }
      })
  }

  build() {
    Column({ space: 20 }) {
      Text(this.title).fontSize(themeFontSize(22, this.theme)).fontFamily(this.theme.fontFamily)
        .fontWeight(FontWeight.Medium).fontColor($r('app.color.content_primary')).width('100%')
      Scroll() {
        Text(this.message).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_primary')).width('100%')
      }.width('100%').constraintSize({ maxHeight: '60%' }).scrollBar(BarState.Auto)
      Row({ space: 12 }) {
        if (this.cancelLabel.length > 0) { this.action(this.cancelLabel, false) }
        this.action(this.confirmLabel, true)
      }.width('100%')
    }.width('90%').constraintSize({ maxWidth: 520, maxHeight: '90%' }).padding(24).borderRadius(28)
      .backgroundColor(this.theme.surface)
  }
}
