import { LogLevel } from './LogModels';

export interface HostOverride {
  host: string;
  value: string;
}

/** 与内核常规设置命令对齐；测速地址继续使用已有应用偏好。 */
export interface GeneralSettings {
  mixedPort: number;
  allowLan: boolean;
  externalController: boolean;
  controllerSecret: string;
  authentication: boolean;
  username: string;
  password: string;
  unifiedDelay: boolean;
  tcpConcurrent: boolean;
  findProcess: boolean;
  autoCloseConnections: boolean;
  onlyProxyTraffic: boolean;
  ipv6: boolean;
  hosts: HostOverride[];
  appendSystemDns: boolean;
  geoMemoryMode: boolean;
  logLevel: LogLevel;
  logCapture: boolean;
}

export type GeneralSettingsChange = (settings: GeneralSettings) => void;
export type GeneralSettingsListener = (settings: GeneralSettings) => void;
