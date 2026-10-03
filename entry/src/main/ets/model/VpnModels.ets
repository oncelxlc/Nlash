export enum VpnState {
  IDLE = 'IDLE',
  REQUESTING_PERMISSION = 'REQUESTING_PERMISSION',
  STARTING = 'STARTING',
  CONNECTED = 'CONNECTED',
  STOPPING = 'STOPPING',
  DISCONNECTED = 'DISCONNECTED',
  ERROR = 'ERROR'
}

export enum CoreServiceState {
  STOPPED = 'STOPPED',
  WAITING_CONFIG = 'WAITING_CONFIG',
  STARTING = 'STARTING',
  RUNNING = 'RUNNING',
  RELOADING = 'RELOADING',
  ERROR = 'ERROR'
}

export enum ProxyState {
  DISABLED = 'DISABLED',
  ENABLING = 'ENABLING',
  ENABLED = 'ENABLED',
  DISABLING = 'DISABLING',
  ERROR = 'ERROR'
}

export enum CoreRestartAction {
  START = 'START',
  RESTART = 'RESTART',
  BLOCKED = 'BLOCKED'
}

export interface VpnStateEvent extends RuntimeLifecycleSnapshot {
  state: VpnState;
}

export interface ProxySessionTiming {
  // Monotonic milliseconds since system startup, including sleep; zero means no start/end.
  sessionStartedAt: number;
  sessionEndedAt: number;
}

export interface RuntimeLifecycleSnapshot extends ProxySessionTiming {
  coreState: CoreServiceState;
  proxyState: ProxyState;
  profileId: string;
  profileSignature: string;
  message: string;
}

export interface VpnStateEnvelope {
  sourceId: string;
  sourceStartedAt: number;
  sequence: number;
  event: VpnStateEvent;
}

export type VpnStateListener = (state: VpnState, message: string) => void;

export type RuntimeLifecycleListener = (snapshot: RuntimeLifecycleSnapshot) => void;
