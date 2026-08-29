export type ConfigurationEditorCloseHandler = () => void;

class ConfigurationEditorService {
  private editorOpen: boolean = false;
  private closeHandler: ConfigurationEditorCloseHandler | undefined = undefined;

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
