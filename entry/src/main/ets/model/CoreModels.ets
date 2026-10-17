/** 原生 Core 的内部生命周期；不表示平台 VPN 是否已开启。 */
export enum CoreRuntimeState {
  STOPPED = 'STOPPED',
  VALIDATING = 'VALIDATING',
  STARTING = 'STARTING',
  RUNNING = 'RUNNING',
  STOPPING = 'STOPPING',
  FAILED = 'FAILED'
}

export enum CoreErrorCode {
  OK = 'OK',
  INVALID_ARGUMENT = 'INVALID_ARGUMENT',
  INVALID_STATE = 'INVALID_STATE',
  CONFIG_INVALID = 'CONFIG_INVALID',
  PROTECT_FAILED = 'PROTECT_FAILED',
  START_FAILED = 'START_FAILED',
  STOP_FAILED = 'STOP_FAILED',
  INTERNAL_ERROR = 'INTERNAL_ERROR',
  UNAVAILABLE = 'UNAVAILABLE'
}

export interface CoreResult {
  ok: boolean;
  code: CoreErrorCode;
  message: string;
}

export interface CoreStartOptions {
  configPath: string;
  workDir: string;
}

/** 宿主创建的 TUN 与本轮 protect 参数，generation 不得跨代理会话复用。 */
export interface CoreProxyOptions {
  tunFd: number;
  mtu: number;
  protectSocketPath: string;
  generation: string;
}

export enum CoreEventType {
  LIFECYCLE = 'LIFECYCLE',
  LOG = 'LOG',
  UNEXPECTED_EXIT = 'UNEXPECTED_EXIT',
  PROTECT_FAILURE = 'PROTECT_FAILURE',
  PROXY_DELAY_PROGRESS = 'PROXY_DELAY_PROGRESS'
}

export interface CoreEvent {
  type: CoreEventType;
  state: CoreRuntimeState;
  code: CoreErrorCode;
  message: string;
}

export type CoreEventListener = (event: CoreEvent) => void;

/** 原生 Core 能力边界，统一配置校验、生命周期、业务命令与事件订阅。 */
export interface CoreClient {
  getVersion(): string;
  validateConfig(configPath: string): Promise<CoreResult>;
  start(options: CoreStartOptions): Promise<CoreResult>;
  enableProxy(options: CoreProxyOptions): Promise<CoreResult>;
  disableProxy(): Promise<CoreResult>;
  isProxyEnabled(): boolean;
  stop(): Promise<void>;
  getState(): CoreRuntimeState;
  subscribe(listener: CoreEventListener): () => void;
  executeCommand(command: string): Promise<string>;
}
