export const coreVersion: () => string;
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
export const validateConfig: (configPath: string) => Promise<NativeCoreResult>;
export const startCore: (options: NativeCoreStartOptions) => Promise<NativeCoreResult>;
export const stopCore: () => Promise<NativeCoreResult>;
export const coreState: () => number;
export const setCoreEventListener: (listener: (event: NativeCoreEvent) => void) => void;
export const clearCoreEventListener: () => void;
export const executeCoreCommand: (command: string) => Promise<string>;
