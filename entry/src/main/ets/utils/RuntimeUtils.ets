import {
  RuntimeMode,
  TrafficSample,
  ProxyNodeSnapshot,
  ProxyGroupSnapshot,
  ProxyDelayResult,
  ProxySelection,
  ProxyDelayOperationSnapshot,
  ConnectionSnapshot,
  DashboardSnapshot,
  FormattedBytes
} from '../model/RuntimeModels';

export class RuntimeRequestMerger {
  private operation: Promise<void> | undefined;

  run(action: () => Promise<void>): Promise<void> {
    const current = this.operation;
    if (current !== undefined) {
      return current;
    }
    const operation = action();
    this.operation = operation;
    operation.then((): void => {
      if (this.operation === operation) {
        this.operation = undefined;
      }
    }, (): void => {
      if (this.operation === operation) {
        this.operation = undefined;
      }
    });
    return operation;
  }
}

export class ProxyDelayOperationRegistry {
  private operations: Map<string, ProxyDelayOperationSnapshot> = new Map<string, ProxyDelayOperationSnapshot>();
  private owners: Map<string, string> = new Map<string, string>();

  start(operationId: string, group: string, proxy: string, targets: string[]): void {
    const uniqueTargets: string[] = [];
    targets.forEach((target: string): void => {
      if (target.length > 0 && !uniqueTargets.includes(target)) {
        uniqueTargets.push(target);
      }
    });
    this.operations.set(operationId, {
      operationId: operationId,
      group: group,
      proxy: proxy,
      pendingProxies: uniqueTargets
    });
    uniqueTargets.forEach((target: string): void => {
      this.owners.set(this.nodeKey(group, target), operationId);
    });
  }

  accept(operationId: string, group: string, proxy: string): boolean {
    const operation = this.operations.get(operationId);
    const key = this.nodeKey(group, proxy);
    if (operation === undefined || operation.group !== group || this.owners.get(key) !== operationId) {
      return false;
    }
    this.owners.delete(key);
    operation.pendingProxies = operation.pendingProxies.filter((name: string): boolean => name !== proxy);
    return true;
  }

  complete(operationId: string): string[] {
    const operation = this.operations.get(operationId);
    if (operation === undefined) {
      return [];
    }
    const pending = operation.pendingProxies.filter((proxy: string): boolean =>
      this.owners.get(this.nodeKey(operation.group, proxy)) === operationId);
    pending.forEach((proxy: string): void => {
      this.owners.delete(this.nodeKey(operation.group, proxy));
    });
    this.operations.delete(operationId);
    return pending;
  }

  invalidate(): void {
    this.operations.clear();
    this.owners.clear();
  }

  hasGroupOperation(group: string): boolean {
    let found = false;
    this.operations.forEach((operation: ProxyDelayOperationSnapshot): void => {
      if (operation.group === group && operation.proxy.length === 0) {
        found = true;
      }
    });
    return found;
  }

  hasDirectOperation(group: string, proxy: string): boolean {
    let found = false;
    this.operations.forEach((operation: ProxyDelayOperationSnapshot): void => {
      if (operation.group === group && operation.proxy === proxy) {
        found = true;
      }
    });
    return found;
  }

  isTesting(group: string, proxy: string): boolean {
    return this.owners.has(this.nodeKey(group, proxy));
  }

  snapshots(): ProxyDelayOperationSnapshot[] {
    const result: ProxyDelayOperationSnapshot[] = [];
    this.operations.forEach((operation: ProxyDelayOperationSnapshot): void => {
      result.push({
        operationId: operation.operationId,
        group: operation.group,
        proxy: operation.proxy,
        pendingProxies: operation.pendingProxies.filter((proxy: string): boolean =>
          this.owners.get(this.nodeKey(operation.group, proxy)) === operation.operationId)
      });
    });
    return result;
  }

  private nodeKey(group: string, proxy: string): string {
    return `${group.length}:${group}:${proxy}`;
  }
}

export function formatBytesParts(value: number): FormattedBytes {
  if (!Number.isFinite(value) || value <= 0) {
    return { value: '0', unit: 'B' };
  }
  const units: string[] = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
  let size = value;
  let unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit += 1;
  }
  const digits = unit === 0 || size >= 100 ? 0 : 1;
  return { value: size.toFixed(digits), unit: units[unit] };
}

export function formatBytes(value: number): string {
  const formatted = formatBytesParts(value);
  return `${formatted.value} ${formatted.unit}`;
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

export function mergeProxyTrafficSnapshot(snapshot: DashboardSnapshot, previous: DashboardSnapshot | undefined,
  baseline: DashboardSnapshot | undefined): DashboardSnapshot {
  // ponytail: count completed VPN sampling intervals; native session counters for exact start/stop boundaries.
  return {
    mode: snapshot.mode,
    uploadSpeed: baseline === undefined ? 0 : snapshot.uploadSpeed,
    downloadSpeed: baseline === undefined ? 0 : snapshot.downloadSpeed,
    uploadTotal: (previous?.uploadTotal ?? 0) + (baseline === undefined ? 0 :
      Math.max(0, snapshot.uploadTotal - baseline.uploadTotal)),
    downloadTotal: (previous?.downloadTotal ?? 0) + (baseline === undefined ? 0 :
      Math.max(0, snapshot.downloadTotal - baseline.downloadTotal)),
    memoryBytes: snapshot.memoryBytes,
    connectionCount: snapshot.connectionCount
  };
}

export function appendTrafficSample(history: TrafficSample[], sample: TrafficSample,
  windowMs: number = 60000): TrafficSample[] {
  if (windowMs <= 0) {
    return [];
  }
  const earliestTimestamp = sample.timestamp - windowMs;
  return history.filter((item: TrafficSample): boolean =>
    item.timestamp >= earliestTimestamp && item.timestamp <= sample.timestamp).concat([sample]);
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

export function preserveTestedProxyDelays(freshGroups: ProxyGroupSnapshot[],
  currentGroups: ProxyGroupSnapshot[]): ProxyGroupSnapshot[] {
  let merged = freshGroups;
  currentGroups.forEach((group: ProxyGroupSnapshot): void => {
    const tested = group.nodes.filter((node: ProxyNodeSnapshot): boolean => node.tested)
      .map((node: ProxyNodeSnapshot): ProxyDelayResult => ({
        proxy: node.name,
        delay: node.delay,
        alive: node.alive
      }));
    if (tested.length > 0) {
      merged = mergeGroupDelay(merged, group.name, tested);
    }
  });
  return merged;
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

export function proxyNodeRenderKey(node: ProxyNodeSnapshot): string {
  return `${node.name.length}:${node.name}:${node.tested ? 1 : 0}:${node.alive ? 1 : 0}:${node.delay}`;
}

export function pruneProxySelections(groups: ProxyGroupSnapshot[],
  selections: ProxySelection[]): ProxySelection[] {
  return selections.filter((selection: ProxySelection): boolean => {
    const group = groups.find((item: ProxyGroupSnapshot): boolean => item.name === selection.group);
    return group !== undefined && group.selectable &&
      group.nodes.some((node: ProxyNodeSnapshot): boolean => node.name === selection.proxy);
  });
}

export function visibleProxyGroups(groups: ProxyGroupSnapshot[], mode: RuntimeMode): ProxyGroupSnapshot[] {
  const visible = groups.filter((group: ProxyGroupSnapshot): boolean => !group.hidden && group.name !== 'GLOBAL');
  if (mode !== RuntimeMode.GLOBAL) {
    return visible;
  }
  const global = groups.find((group: ProxyGroupSnapshot): boolean => !group.hidden && group.name === 'GLOBAL');
  return global === undefined ? visible : [global].concat(visible);
}

export function resolveSelectedProxyGroup(groups: ProxyGroupSnapshot[], mode: RuntimeMode,
  savedGroup: string): string {
  const visible = visibleProxyGroups(groups, mode);
  if (visible.some((group: ProxyGroupSnapshot): boolean => group.name === savedGroup)) {
    return savedGroup;
  }
  if (mode === RuntimeMode.GLOBAL && visible.some((group: ProxyGroupSnapshot): boolean => group.name === 'GLOBAL')) {
    return 'GLOBAL';
  }
  return visible[0]?.name ?? '';
}
