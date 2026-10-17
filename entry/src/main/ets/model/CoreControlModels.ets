/** 跨进程事件信封；command 内层仍是 Go 或宿主可识别的 JSON 命令字符串。 */
export interface CoreCommandEnvelope {
  version: number;
  requestId: string;
  command: string;
}

/** requestId 与命令信封对应；response 保留业务响应 JSON。 */
export interface CoreResponseEnvelope {
  version: number;
  requestId: string;
  response: string;
}

/** 单节点增量测速结果；operationId 用于关联任务，delay 单位为毫秒，失败时为 -1。 */
export interface ProxyDelayProgress {
  operationId: string;
  group: string;
  proxy: string;
  delay: number;
  alive: boolean;
  errorCode?: string;
}

export type ProxyDelayProgressListener = (progress: ProxyDelayProgress) => void;
