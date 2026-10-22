import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo, picker } from '@kit.CoreFileKit';
import { LogRecord, LogSnapshot } from '../model/LogModels';
import { buildLogFileName, formatLogExport, isValidLogSnapshot } from '../utils/LogUtils';
import { runtimeControlService } from './RuntimeControlService';

class LogService {
  async load(): Promise<LogSnapshot> {
    const result = await runtimeControlService.execute<LogSnapshot>('logSnapshot');
    if (!result.ok || result.data === undefined) { throw new Error(result.message || '读取日志失败'); }
    if (!isValidLogSnapshot(result.data)) { throw new Error('日志响应无效'); }
    return result.data;
  }

  async exportLogs(context: common.UIAbilityContext, records: LogRecord[]): Promise<boolean> {
    if (records.length === 0) { throw new Error('没有可导出的日志'); }
    // 固定点击时的结果，文件选择期间的新日志不会改变本次导出。
    const content = new util.TextEncoder().encodeInto(formatLogExport(records)).buffer;
    const name = buildLogFileName(context.resourceManager.getStringByNameSync('app_name'), Date.now());
    const paths = await new picker.DocumentViewPicker(context).save({
      newFileNames: [name], fileSuffixChoices: ['日志文件|.log']
    });
    if (paths.length === 0) { return false; }
    const file = await fileIo.open(paths[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      let written = 0;
      while (written < content.byteLength) {
        const count = await fileIo.write(file.fd, content.slice(written));
        if (count <= 0) { throw new Error('日志未完整写入，请检查存储空间后重试'); }
        written += count;
      }
      await fileIo.fsync(file.fd);
    } finally { await fileIo.close(file); }
    return true;
  }
}

export const logService = new LogService();
