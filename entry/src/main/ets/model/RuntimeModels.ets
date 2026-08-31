export enum RuntimeMode {
  RULE = 'rule',
  GLOBAL = 'global',
  DIRECT = 'direct'
}

export enum ProxySnapshotSource {
  NONE = 'none',
  CONFIG = 'config',
  RUNTIME = 'runtime'
}

export interface TrafficSample {
  timestamp: number;
  uploadSpeed: number;
  downloadSpeed: number;
}

export interface DashboardSnapshot {
  mode: RuntimeMode;
  uploadSpeed: number;
  downloadSpeed: number;
  uploadTotal: number;
  downloadTotal: number;
  memoryBytes: number;
  connectionCount: number;
}

export interface ProxyNodeSnapshot {
  name: string;
  type: string;
  alive: boolean;
  tested: boolean;
  delay: number;
  udp: boolean;
}

export interface ProxyGroupSnapshot {
  name: string;
  type: string;
  selected: string;
  selectable: boolean;
  hidden: boolean;
  nodes: ProxyNodeSnapshot[];
}

export interface ProxySnapshot {
  source: ProxySnapshotSource;
  mode: RuntimeMode;
  groups: ProxyGroupSnapshot[];
}

export interface ProxyDelayResult {
  proxy: string;
  delay: number;
  alive: boolean;
  errorCode?: string;
}

export interface GroupDelayResult {
  group: string;
  results: ProxyDelayResult[];
}

export interface ProxySelection {
  group: string;
  proxy: string;
}

export interface ProxyDelayOperationSnapshot {
  operationId: string;
  group: string;
  proxy: string;
  pendingProxies: string[];
}

export interface PublicNetworkSnapshot {
  publicIpv4: string;
  country: string;
  countryCode: string;
  checking: boolean;
  lastSuccessAt?: number;
  errorMessage: string;
}

export interface ConnectionSnapshot {
  id: string;
  network: string;
  type: string;
  host: string;
  destination: string;
  source: string;
  process: string;
  start: number;
  upload: number;
  download: number;
  chains: string[];
  rule: string;
  rulePayload: string;
}

export interface ConnectionsSnapshot {
  uploadTotal: number;
  downloadTotal: number;
  memoryBytes: number;
  connections: ConnectionSnapshot[];
}

export interface RequestRecord {
  id: string;
  network: string;
  host: string;
  destination: string;
  process: string;
  start: number;
  end: number;
  upload: number;
  download: number;
  chains: string[];
  rule: string;
  rulePayload: string;
  active: boolean;
}

export interface DelayTestResult {
  proxy: string;
  delay: number;
}

export interface RuntimeCommandResponse<T> {
  ok: boolean;
  code: string;
  message: string;
  data?: T;
}

export interface RuntimeStoreSnapshot {
  coreAvailable: boolean;
  refreshing: boolean;
  previewLoading: boolean;
  dashboard?: DashboardSnapshot;
  proxies: ProxyGroupSnapshot[];
  proxySource: ProxySnapshotSource;
  proxyMode: RuntimeMode;
  proxySelections: ProxySelection[];
  selectedProxyGroup: string;
  delayOperations: ProxyDelayOperationSnapshot[];
  trafficHistory: TrafficSample[];
  connections: ConnectionSnapshot[];
  requests: RequestRecord[];
  busyKey: string;
}

export type RuntimeStoreListener = (snapshot: RuntimeStoreSnapshot) => void;

export interface FormattedBytes {
  value: string;
  unit: string;
}
