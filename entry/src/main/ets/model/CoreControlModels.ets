export interface CoreCommandEnvelope {
  version: number;
  requestId: string;
  command: string;
}

export interface CoreResponseEnvelope {
  version: number;
  requestId: string;
  response: string;
}

export interface ProxyDelayProgress {
  operationId: string;
  group: string;
  proxy: string;
  delay: number;
  alive: boolean;
  errorCode?: string;
}

export type ProxyDelayProgressListener = (progress: ProxyDelayProgress) => void;
