/** 面向旧 VPN 状态订阅者的展示状态，由 ProxyState 映射得到。 */
export enum VpnState {
  IDLE = 'IDLE',
  REQUESTING_PERMISSION = 'REQUESTING_PERMISSION',
  STARTING = 'STARTING',
  CONNECTED = 'CONNECTED',
  STOPPING = 'STOPPING',
  DISCONNECTED = 'DISCONNECTED',
  ERROR = 'ERROR'
}

/** 宿主管理的 Core 状态，可在系统代理关闭时保持 RUNNING。 */
export enum CoreServiceState {
  STOPPED = 'STOPPED',
  WAITING_CONFIG = 'WAITING_CONFIG',
  STARTING = 'STARTING',
  RUNNING = 'RUNNING',
  RELOADING = 'RELOADING',
  ERROR = 'ERROR'
}

/** 系统流量接管状态，与 Core 本身的生命周期独立。 */
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

/** 宿主的权威生命周期视图；profileSignature 同时区分配置身份与内容更新时间。 */
export interface RuntimeLifecycleSnapshot extends ProxySessionTiming {
  coreState: CoreServiceState;
  proxyState: ProxyState;
  profileId: string;
  profileSignature: string;
  message: string;
}

/** 来源启动时间判定新宿主，同一来源使用递增 sequence 过滤重复和乱序状态。 */
export interface VpnStateEnvelope {
  sourceId: string;
  sourceStartedAt: number;
  sequence: number;
  event: VpnStateEvent;
}

export type VpnStateListener = (state: VpnState, message: string) => void;

export type RuntimeLifecycleListener = (snapshot: RuntimeLifecycleSnapshot) => void;
