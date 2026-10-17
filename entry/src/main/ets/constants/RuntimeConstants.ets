import { RuntimeMode } from '../model/RuntimeModels';

export const DEFAULT_RUNTIME_MODE: RuntimeMode = RuntimeMode.RULE;
// UI 与通知读取运行快照的轮询间隔，单位为毫秒。
export const RUNTIME_REFRESH_INTERVAL_MS: number = 2000;
