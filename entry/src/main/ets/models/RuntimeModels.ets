export enum RuntimeMode {
  RULE = 'rule',
  GLOBAL = 'global',
  DIRECT = 'direct'
}

export const DEFAULT_RUNTIME_MODE: RuntimeMode = RuntimeMode.RULE;

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
  groups: ProxyGroupSnapshot[];
}

export interface ProxyDelayResult {
  proxy: string;
  delay: number;
  alive: boolean;
}

export interface GroupDelayResult {
  group: string;
  results: ProxyDelayResult[];
}

export interface ProxySelection {
  group: string;
  proxy: string;
}

export interface LocalNetworkSnapshot {
  localIpv4: string;
  checking: boolean;
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
  available: boolean;
  refreshing: boolean;
  previewLoading: boolean;
  dashboard?: DashboardSnapshot;
  proxies: ProxyGroupSnapshot[];
  proxySource: ProxySnapshotSource;
  proxySelections: ProxySelection[];
  trafficHistory: TrafficSample[];
  connections: ConnectionSnapshot[];
  requests: RequestRecord[];
  busyKey: string;
}

export type RuntimeStoreListener = (snapshot: RuntimeStoreSnapshot) => void;

export function formatBytes(value: number): string {
  if (!Number.isFinite(value) || value <= 0) {
    return '0 B';
  }
  const units: string[] = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  let size = value;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  const digits = unit === 0 || size >= 100 ? 0 : 1;
  return `${size.toFixed(digits)} ${units[unit]}`;
}

export function formatSpeed(value: number): string {
  return `${formatBytes(value)}/s`;
}

export function connectionTitle(connection: ConnectionSnapshot): string {
  if (connection.host.length > 0) {
    return connection.host;
  }
  return connection.destination;
}

export function appendTrafficSample(history: TrafficSample[], sample: TrafficSample,
  limit: number = 60): TrafficSample[] {
  if (limit <= 0) {
    return [];
  }
  const next = history.slice();
  next.push(sample);
  return next.slice(Math.max(0, next.length - limit));
}

export function mergeGroupDelay(groups: ProxyGroupSnapshot[], groupName: string,
  results: ProxyDelayResult[]): ProxyGroupSnapshot[] {
  const resultByName = new Map<string, ProxyDelayResult>();
  results.forEach((result: ProxyDelayResult): void => {
    resultByName.set(result.proxy, result);
  });
  return groups.map((group: ProxyGroupSnapshot): ProxyGroupSnapshot => {
    if (group.name !== groupName) {
      return group;
    }
    return {
      name: group.name,
      type: group.type,
      selected: group.selected,
      selectable: group.selectable,
      hidden: group.hidden,
      nodes: group.nodes.map((node: ProxyNodeSnapshot): ProxyNodeSnapshot => {
        const result = resultByName.get(node.name);
        if (result === undefined) {
          return node;
        }
        return {
          name: node.name,
          type: node.type,
          alive: result.alive,
          tested: true,
          delay: result.delay,
          udp: node.udp
        };
      })
    };
  });
}

export function resetGroupDelay(groups: ProxyGroupSnapshot[], groupName: string,
  proxyName: string = ''): ProxyGroupSnapshot[] {
  return groups.map((group: ProxyGroupSnapshot): ProxyGroupSnapshot => {
    if (group.name !== groupName) {
      return group;
    }
    return {
      name: group.name,
      type: group.type,
      selected: group.selected,
      selectable: group.selectable,
      hidden: group.hidden,
      nodes: group.nodes.map((node: ProxyNodeSnapshot): ProxyNodeSnapshot => {
        if (proxyName.length > 0 && node.name !== proxyName) {
          return node;
        }
        return {
          name: node.name,
          type: node.type,
          alive: false,
          tested: false,
          delay: 0,
          udp: node.udp
        };
      })
    };
  });
}

export function failPendingGroupDelay(groups: ProxyGroupSnapshot[], groupName: string,
  proxyName: string = ''): ProxyGroupSnapshot[] {
  return groups.map((group: ProxyGroupSnapshot): ProxyGroupSnapshot => {
    if (group.name !== groupName) {
      return group;
    }
    return {
      name: group.name,
      type: group.type,
      selected: group.selected,
      selectable: group.selectable,
      hidden: group.hidden,
      nodes: group.nodes.map((node: ProxyNodeSnapshot): ProxyNodeSnapshot => {
        if ((proxyName.length > 0 && node.name !== proxyName) || node.tested) {
          return node;
        }
        return {
          name: node.name,
          type: node.type,
          alive: false,
          tested: true,
          delay: -1,
          udp: node.udp
        };
      })
    };
  });
}

export function proxyDelayLabel(node: ProxyNodeSnapshot, testing: boolean): string {
  if (testing) {
    return '…';
  }
  if (!node.tested) {
    return '⚡';
  }
  return node.alive && node.delay > 0 ? `${node.delay}ms` : 'Error';
}

export function pruneProxySelections(groups: ProxyGroupSnapshot[],
  selections: ProxySelection[]): ProxySelection[] {
  return selections.filter((selection: ProxySelection): boolean => {
    const group = groups.find((item: ProxyGroupSnapshot): boolean => item.name === selection.group);
    return group !== undefined && group.selectable &&
      group.nodes.some((node: ProxyNodeSnapshot): boolean => node.name === selection.proxy);
  });
}
