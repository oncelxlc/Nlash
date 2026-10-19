export enum RuntimeMode {
  RULE = 'rule',
  GLOBAL = 'global',
  DIRECT = 'direct'
}

/** 区分无数据、静态配置预览与运行 Core 快照，供页面决定可执行的操作。 */
export enum ProxySnapshotSource {
  NONE = 'none',
  CONFIG = 'config',
  RUNTIME = 'runtime'
}

/** timestamp 为 Unix 毫秒，上传和下载速率为字节/秒。 */
export interface TrafficSample {
  timestamp: number;
  uploadSpeed: number;
  downloadSpeed: number;
}

/** 图表局部坐标及曲线切线斜率，供 Canvas 构建平滑路径。 */
export interface TrafficChartPoint {
  x: number;
  y: number;
  slope: number;
}

/** 与 Go 仪表盘响应对齐；速率为字节/秒，总量和内存为字节。 */
export interface DashboardSnapshot {
  mode: RuntimeMode;
  uploadSpeed: number;
  downloadSpeed: number;
  uploadTotal: number;
  downloadTotal: number;
  memoryBytes: number;
  connectionCount: number;
}

/** tested 区分未知与失败；仅 alive 且 delay > 0 时展示有效毫秒延迟。 */
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

/** proxy 为空表示整组测速，pendingProxies 只包含仍由该任务负责的节点。 */
export interface ProxyDelayOperationSnapshot {
  operationId: string;
  group: string;
  proxy: string;
  pendingProxies: string[];
}

export enum IpNetworkType {
  UNKNOWN = 'unknown',
  HOSTING = 'hosting',
  MOBILE = 'mobile',
  NON_HOSTING = 'nonHosting'
}

export enum IpQuality {
  UNKNOWN = 'unknown',
  GOOD = 'good',
  NORMAL = 'normal',
  POOR = 'poor'
}

/** 保留上次成功出口；质量为 IPQuery 风险信息的本地分级，不代表网络速度。 */
export interface PublicNetworkSnapshot {
  publicIpv4: string;
  country: string;
  countryCode: string;
  organization?: string;
  networkType?: IpNetworkType;
  quality?: IpQuality;
  riskScore?: number;
  qualityError?: string;
  checking: boolean;
  lastSuccessAt?: number;
  errorMessage: string;
}

/** 运行中连接的展示副本，start 为 Unix 毫秒，upload/download 为该连接累计字节。 */
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
  uploadSpeed?: number;
  downloadSpeed?: number;
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

/** UI 内存中的有限请求历史；连接消失后标记 inactive 并冻结结束时间及流量。 */
export interface RequestRecord {
  id: string;
  network: string;
  host: string;
  destination: string;
  source?: string;
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

/** 命令传输成功不等于业务成功，调用方须检查 ok，并按命令判断 data 是否必需。 */
export interface RuntimeCommandResponse<T> {
  ok: boolean;
  code: string;
  message: string;
  data?: T;
}

/** 页面订阅的聚合视图；busyKey 表示互斥操作，独立测速任务由 delayOperations 描述。 */
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
