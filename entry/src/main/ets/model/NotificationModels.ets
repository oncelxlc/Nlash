/** 通知文案与操作意图，不包含系统任务 ID，供构建系统通知请求时复用。 */
export interface VpnNotificationPresentation {
  title: string;
  text: string;
  additionalText: string;
  showPauseAction: boolean;
}
