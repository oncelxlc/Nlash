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
  tunFd: number;
  mtu: number;
  protectSocketPath: string;
  generation: string;
}

export enum CoreEventType {
  LIFECYCLE = 'LIFECYCLE',
  LOG = 'LOG',
  UNEXPECTED_EXIT = 'UNEXPECTED_EXIT',
  PROTECT_FAILURE = 'PROTECT_FAILURE'
}

export interface CoreEvent {
  type: CoreEventType;
  state: CoreRuntimeState;
  code: CoreErrorCode;
  message: string;
}

export type CoreEventListener = (event: CoreEvent) => void;

export interface CoreClient {
  getVersion(): string;
  validateConfig(configPath: string): Promise<CoreResult>;
  start(options: CoreStartOptions): Promise<CoreResult>;
  stop(): Promise<void>;
  getState(): CoreRuntimeState;
  subscribe(listener: CoreEventListener): () => void;
  executeCommand(command: string): Promise<string>;
}
