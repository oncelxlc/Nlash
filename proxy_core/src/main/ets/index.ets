import nativeCore from 'libproxy_core.so';

export interface NativeCoreResult {
  ok: boolean;
  code: number;
  message: string;
}

export interface NativeCoreStartOptions {
  configPath: string;
  workDir: string;
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

export function stopCore(): Promise<NativeCoreResult> {
  return nativeCore.stopCore();
}

export function coreState(): number {
  return nativeCore.coreState();
}

export function setCoreEventListener(listener: (event: NativeCoreEvent) => void): void {
  nativeCore.setCoreEventListener(listener);
}

export function clearCoreEventListener(): void {
  nativeCore.clearCoreEventListener();
}

export function executeCoreCommand(command: string): Promise<string> {
  return nativeCore.executeCoreCommand(command);
}
