import { hidebug } from '@kit.PerformanceAnalysisKit';

/** 异步读取 UI 进程 PSS，避免在主线程扫描 smaps；系统返回 KB，页面统一使用字节。 */
export async function readAppMemoryBytes(): Promise<number> {
  const memory = await hidebug.getAppNativeMemInfoAsync();
  const bytes = Number(memory.pss) * 1024;
  if (!Number.isFinite(bytes) || bytes < 0) {
    throw new Error('应用内存数据无效');
  }
  return bytes;
}
