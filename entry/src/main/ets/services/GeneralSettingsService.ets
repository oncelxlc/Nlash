import { GeneralSettings, GeneralSettingsChange, GeneralSettingsListener } from '../model/GeneralSettingsModels';
import { runtimeControlService } from './RuntimeControlService';

export class GeneralSettingsService {
  private revision: number = 0;
  private settings: GeneralSettings | undefined;
  private changes: GeneralSettingsChange[] = [];
  private saveQueue: Promise<void> = Promise.resolve();
  private listeners: Set<GeneralSettingsListener> = new Set<GeneralSettingsListener>();

  isSaving(): boolean { return this.changes.length > 0; }

  subscribe(listener: GeneralSettingsListener): () => void {
    this.listeners.add(listener);
    if (this.settings !== undefined) { listener(this.currentSettings(this.settings)); }
    return (): void => { this.listeners.delete(listener); };
  }

  async load(): Promise<GeneralSettings> {
    await this.saveQueue;
    const revision = this.revision;
    const result = await runtimeControlService.execute<GeneralSettings>('generalSettings');
    if (!result.ok || result.data === undefined) { throw new Error(result.message || '读取常规设置失败'); }
    // 保存后返回的旧读取结果不能恢复已关闭的入口。
    if (revision === this.revision) {
      this.settings = result.data;
      AppStorage.setOrCreate('logCaptureEnabled', result.data.logCapture);
      this.publish();
    }
    return this.currentSettings(this.settings ?? result.data);
  }

  // 保存只合并本次修改；未完成的修改继续投影到界面，失败不会撤销其他选项。
  update(change: GeneralSettingsChange): Promise<void> {
    if (this.settings === undefined) { return Promise.reject(new Error('设置尚未读取，请稍后重试')); }
    this.revision += 1;
    this.changes.push(change);
    this.publish();
    const operation = this.saveQueue.then(async (): Promise<void> => {
      const saved = this.settings;
      if (saved === undefined) { throw new Error('设置尚未读取，请稍后重试'); }
      const next = this.copy(saved);
      change(next);
      try { this.settings = await this.save(next); }
      finally {
        this.changes.shift();
        this.publish();
      }
    });
    this.saveQueue = operation.then((): void => {}, (): void => {});
    return operation;
  }

  async save(settings: GeneralSettings): Promise<GeneralSettings> {
    const result = await runtimeControlService.execute<GeneralSettings>('saveGeneralSettings', settings, 120000);
    if (!result.ok || result.data === undefined) { throw new Error(result.message || '保存常规设置失败'); }
    this.settings = result.data;
    this.revision += 1;
    AppStorage.setOrCreate('logCaptureEnabled', result.data.logCapture);
    return result.data;
  }

  private copy(settings: GeneralSettings): GeneralSettings {
    return JSON.parse(JSON.stringify(settings)) as GeneralSettings;
  }

  private currentSettings(settings: GeneralSettings): GeneralSettings {
    const current = this.copy(settings);
    this.changes.forEach((change: GeneralSettingsChange): void => { change(current); });
    return current;
  }

  private publish(): void {
    const saved = this.settings;
    if (saved === undefined) { return; }
    this.listeners.forEach((listener: GeneralSettingsListener): void => listener(this.currentSettings(saved)));
  }
}

export const generalSettingsService = new GeneralSettingsService();
