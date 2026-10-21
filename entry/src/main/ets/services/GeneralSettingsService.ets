import { GeneralSettings } from '../model/GeneralSettingsModels';
import { runtimeControlService } from './RuntimeControlService';

class GeneralSettingsService {
  async load(): Promise<GeneralSettings> {
    const result = await runtimeControlService.execute<GeneralSettings>('generalSettings');
    if (!result.ok || result.data === undefined) { throw new Error(result.message || '读取常规设置失败'); }
    return result.data;
  }

  async save(settings: GeneralSettings): Promise<GeneralSettings> {
    const result = await runtimeControlService.execute<GeneralSettings>('saveGeneralSettings', settings, 120000);
    if (!result.ok || result.data === undefined) { throw new Error(result.message || '保存常规设置失败'); }
    return result.data;
  }
}

export const generalSettingsService = new GeneralSettingsService();
