import { GeneralSettings } from '../model/GeneralSettingsModels';

export const DEFAULT_GENERAL_SETTINGS: GeneralSettings = {
  mixedPort: 7890,
  allowLan: false,
  externalController: false,
  controllerSecret: '',
  authentication: false,
  username: '',
  password: '',
  unifiedDelay: true,
  tcpConcurrent: true,
  findProcess: false,
  autoCloseConnections: true,
  onlyProxyTraffic: false,
  ipv6: false,
  hosts: [],
  appendSystemDns: false,
  geoMemoryMode: true
};
