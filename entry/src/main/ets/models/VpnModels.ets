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

export function resolveCoreRestartAction(state: VpnState): CoreRestartAction {
  if (state === VpnState.REQUESTING_PERMISSION || state === VpnState.STARTING || state === VpnState.STOPPING) {
    return CoreRestartAction.BLOCKED;
  }
  if (state === VpnState.IDLE || state === VpnState.DISCONNECTED) {
    return CoreRestartAction.START;
  }
  return CoreRestartAction.RESTART;
}

export function formatVpnRunDuration(totalSeconds: number): string {
  const seconds = Number.isFinite(totalSeconds) && totalSeconds > 0 ? Math.floor(totalSeconds) : 0;
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor(seconds % 3600 / 60);
  const remainingSeconds = seconds % 60;
  return `${durationPart(hours)}:${durationPart(minutes)}:${durationPart(remainingSeconds)}`;
}

export function resolveVpnConnectedAt(previousState: VpnState, state: VpnState,
  connectedAt: number, now: number): number {
  if (state === VpnState.CONNECTED && previousState !== VpnState.CONNECTED) {
    return now;
  }
  if (state === VpnState.IDLE || state === VpnState.DISCONNECTED || state === VpnState.ERROR) {
    return 0;
  }
  return connectedAt;
}

function durationPart(value: number): string {
  return value < 10 ? `0${value}` : value.toString();
}

export interface VpnStateEvent {
  state: VpnState;
  coreState: CoreServiceState;
  proxyState: ProxyState;
  profileId: string;
  profileSignature: string;
  message: string;
}

export interface RuntimeLifecycleSnapshot {
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

export const VPN_STATE_EVENT = 'nlash.vpn.state.changed';
export const VPN_STATE_COMMON_EVENT = 'com.zhexian.nlash.event.VPN_STATE_CHANGED';
export const VPN_BUNDLE_NAME = 'com.zhexian.nlash';

export function encodeVpnStateEnvelope(envelope: VpnStateEnvelope): string {
  return JSON.stringify(envelope);
}

export function decodeVpnStateEnvelope(data: string): VpnStateEnvelope | undefined {
  let envelope: VpnStateEnvelope;
  try {
    envelope = JSON.parse(data) as VpnStateEnvelope;
  } catch (error) {
    return undefined;
  }
  if (typeof envelope.sourceId !== 'string' || envelope.sourceId.length === 0 || envelope.sourceId.length > 64 ||
    !Number.isFinite(envelope.sourceStartedAt) || envelope.sourceStartedAt % 1 !== 0 || envelope.sourceStartedAt <= 0 ||
    !Number.isFinite(envelope.sequence) || envelope.sequence % 1 !== 0 || envelope.sequence <= 0 ||
    envelope.event === undefined || typeof envelope.event.message !== 'string' || envelope.event.message.length > 1024 ||
    typeof envelope.event.profileId !== 'string' || envelope.event.profileId.length > 128 ||
    typeof envelope.event.profileSignature !== 'string' || envelope.event.profileSignature.length > 1024 ||
    !isCoreServiceState(envelope.event.coreState) || !isProxyState(envelope.event.proxyState)) {
    return undefined;
  }
  switch (envelope.event.state) {
    case VpnState.IDLE:
    case VpnState.REQUESTING_PERMISSION:
    case VpnState.STARTING:
    case VpnState.CONNECTED:
    case VpnState.STOPPING:
    case VpnState.DISCONNECTED:
    case VpnState.ERROR:
      return envelope;
    default:
      return undefined;
  }
}

export function vpnStateFromProxyState(state: ProxyState): VpnState {
  if (state === ProxyState.ENABLING) {
    return VpnState.STARTING;
  }
  if (state === ProxyState.ENABLED) {
    return VpnState.CONNECTED;
  }
  if (state === ProxyState.DISABLING) {
    return VpnState.STOPPING;
  }
  if (state === ProxyState.ERROR) {
    return VpnState.ERROR;
  }
  return VpnState.DISCONNECTED;
}

export function resolveProxyConnectedAt(previousState: ProxyState, state: ProxyState,
  connectedAt: number, now: number): number {
  if (state === ProxyState.ENABLED && previousState !== ProxyState.ENABLED &&
    previousState !== ProxyState.DISABLING) {
    return now;
  }
  if (state === ProxyState.DISABLED || state === ProxyState.ERROR) {
    return 0;
  }
  return connectedAt;
}

function isCoreServiceState(state: CoreServiceState): boolean {
  switch (state) {
    case CoreServiceState.STOPPED:
    case CoreServiceState.WAITING_CONFIG:
    case CoreServiceState.STARTING:
    case CoreServiceState.RUNNING:
    case CoreServiceState.RELOADING:
    case CoreServiceState.ERROR:
      return true;
    default:
      return false;
  }
}

function isProxyState(state: ProxyState): boolean {
  switch (state) {
    case ProxyState.DISABLED:
    case ProxyState.ENABLING:
    case ProxyState.ENABLED:
    case ProxyState.DISABLING:
    case ProxyState.ERROR:
      return true;
    default:
      return false;
  }
}

export class VpnStateSequenceTracker {
  private sourceId: string = '';
  private sourceStartedAt: number = 0;
  private sequence: number = 0;

  accept(envelope: VpnStateEnvelope): boolean {
    if (envelope.sourceStartedAt > this.sourceStartedAt) {
      this.sourceId = envelope.sourceId;
      this.sourceStartedAt = envelope.sourceStartedAt;
      this.sequence = envelope.sequence;
      return true;
    }
    if (envelope.sourceStartedAt !== this.sourceStartedAt || envelope.sourceId !== this.sourceId ||
      envelope.sequence <= this.sequence) {
      return false;
    }
    this.sequence = envelope.sequence;
    return true;
  }
}
