import {
  VpnState, CoreServiceState, ProxyState, CoreRestartAction, VpnStateEnvelope, ProxySessionTiming
} from '../model/VpnModels';
import { vpnExtension } from '@kit.NetworkKit';

/** 与 Go configureHarmonyTun 保持一致；IPv6 改变时由宿主重建系统 TUN。 */
export function buildPlatformVpnConfig(mtu: number, ipv6: boolean): vpnExtension.VpnConfig {
  const config: vpnExtension.VpnConfig = {
    addresses: [{ address: { address: '172.19.0.1', family: 1 }, prefixLength: 30 }],
    routes: [{
      interface: 'vpn-tun', destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
      gateway: { address: '0.0.0.0', family: 1 }, hasGateway: false, isDefaultRoute: true
    }],
    dnsAddresses: ['1.1.1.1'], mtu: mtu, isIPv4Accepted: true, isIPv6Accepted: ipv6,
    isInternal: false, isBlocking: false
  };
  if (ipv6) {
    config.addresses.push({ address: { address: 'fdfe:dcba:9876::1', family: 2 }, prefixLength: 126 });
    config.routes?.push({
      interface: 'vpn-tun', destination: { address: { address: '::', family: 2 }, prefixLength: 0 },
      gateway: { address: '::', family: 2 }, hasGateway: false, isDefaultRoute: true
    });
  }
  return config;
}

/** 使用系统启动后的单调毫秒计时；重启代理资源时可保留同一会话，显式结束后才重新计时。 */
export class ProxySessionTimer {
  private startedAt: number = 0;
  private endedAt: number = 0;

  connected(now: number): void {
    if (this.startedAt === 0 || this.endedAt > 0) {
      this.startedAt = Math.max(1, now);
      this.endedAt = 0;
    }
  }

  finish(now: number): void {
    if (this.startedAt > 0 && this.endedAt === 0) {
      this.endedAt = Math.max(this.startedAt, now);
    }
  }

  getSnapshot(): ProxySessionTiming {
    return { sessionStartedAt: this.startedAt, sessionEndedAt: this.endedAt };
  }
}

/** 已结束会话显示为零，调用方须传入与起止时间相同来源的单调时钟。 */
export function proxySessionElapsedSeconds(startedAt: number, endedAt: number, now: number): number {
  if (startedAt <= 0 || endedAt > 0) {
    return 0;
  }
  return Math.max(0, Math.floor((now - startedAt) / 1000));
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

export function encodeVpnStateEnvelope(envelope: VpnStateEnvelope): string {
  return JSON.stringify(envelope);
}

/** 跨进程信任边界：校验来源、枚举、字段上限与起止时间关系，不接受部分有效的状态。 */
export function decodeVpnStateEnvelope(data: string): VpnStateEnvelope | undefined {
  let envelope: VpnStateEnvelope;
  try {
    envelope = JSON.parse(data) as VpnStateEnvelope;
  } catch (error) {
    return undefined;
  }
  if (envelope === null || typeof envelope !== 'object' ||
    typeof envelope.sourceId !== 'string' || envelope.sourceId.length === 0 || envelope.sourceId.length > 64 ||
    !Number.isFinite(envelope.sourceStartedAt) || envelope.sourceStartedAt % 1 !== 0 || envelope.sourceStartedAt <= 0 ||
    !Number.isFinite(envelope.sequence) || envelope.sequence % 1 !== 0 || envelope.sequence <= 0 ||
    envelope.event === undefined || envelope.event === null ||
    !Number.isFinite(envelope.event.sessionStartedAt) || envelope.event.sessionStartedAt < 0 ||
    !Number.isFinite(envelope.event.sessionEndedAt) || envelope.event.sessionEndedAt < 0 ||
    (envelope.event.sessionEndedAt > 0 && (envelope.event.sessionStartedAt === 0 ||
      envelope.event.sessionEndedAt < envelope.event.sessionStartedAt)) ||
    typeof envelope.event.message !== 'string' || envelope.event.message.length > 1024 ||
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

/** 关闭失败恢复 ENABLED 时沿用原连接时间，避免把仍在工作的代理视为新连接。 */
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

/** 只接收更新宿主或当前宿主更大的序号，防止迟到的广播让 UI 状态倒退。 */
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
