import nativeCore from 'libproxy_core.so';

/** 原生业务结果；code、state、type 使用跨语言 ABI 数值，由应用层转换为领域枚举。 */
export interface NativeCoreResult {
  ok: boolean;
  code: number;
  message: string;
}

/** Core 工作目录用于规则与缓存；启动 Core 本身不启用系统 VPN。 */
export interface NativeCoreStartOptions {
  configPath: string;
  workDir: string;
}

/** 平台 TUN 与 protect 通道参数；generation 必须匹配当前代理会话。 */
export interface NativeCoreProxyOptions {
  tunFd: number;
  mtu: number;
  protectSocketPath: string;
  generation: string;
}

export interface NativeCoreEvent {
  type: number;
  state: number;
  code: number;
  message: string;
}

export function coreVersion(): string {
  return nativeCore.coreVersion();
}

export function validateConfig(configPath: string): Promise<NativeCoreResult> {
  return nativeCore.validateConfig(configPath);
}

export function startCore(options: NativeCoreStartOptions): Promise<NativeCoreResult> {
  return nativeCore.startCore(options);
}

export function enableCoreProxy(options: NativeCoreProxyOptions): Promise<NativeCoreResult> {
  return nativeCore.enableCoreProxy(options);
}

export function disableCoreProxy(): Promise<NativeCoreResult> {
  return nativeCore.disableCoreProxy();
}

export function coreProxyEnabled(): boolean {
  return nativeCore.coreProxyEnabled();
}

export function stopCore(): Promise<NativeCoreResult> {
  return nativeCore.stopCore();
}

export function coreState(): number {
  return nativeCore.coreState();
}

/** 替换当前原生监听器；应用层的多订阅分发由 CoreClient 统一管理。 */
export function setCoreEventListener(listener: (event: NativeCoreEvent) => void): void {
  nativeCore.setCoreEventListener(listener);
}

export function clearCoreEventListener(): void {
  nativeCore.clearCoreEventListener();
}

/** JSON 命令与响应保持原样穿透，具体业务字段由调用方和 Go 核心校验。 */
export function executeCoreCommand(command: string): Promise<string> {
  return nativeCore.executeCoreCommand(command);
}
