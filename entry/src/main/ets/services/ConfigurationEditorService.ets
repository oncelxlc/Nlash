export type ConfigurationEditorCloseHandler = () => void;

/** 将系统返回操作交给配置编辑器优先处理，避免编辑面板打开时切走整个页面。 */
class ConfigurationEditorService {
  private editorOpen: boolean = false;
  private closeHandler: ConfigurationEditorCloseHandler | undefined = undefined;

  /** 解绑时核对处理器身份，防止旧页面销毁时清掉新页面的绑定。 */
  bind(closeHandler: ConfigurationEditorCloseHandler): () => void {
    this.closeHandler = closeHandler;
    return (): void => {
      if (this.closeHandler === closeHandler) {
        this.closeHandler = undefined;
        this.editorOpen = false;
      }
    };
  }

  setOpen(open: boolean): void {
    this.editorOpen = open;
  }

  handleBack(): boolean {
    if (!this.editorOpen || this.closeHandler === undefined) {
      return false;
    }
    this.closeHandler();
    return true;
  }
}

export const configurationEditorService = new ConfigurationEditorService();
