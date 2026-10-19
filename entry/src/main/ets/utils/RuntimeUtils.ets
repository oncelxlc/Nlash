import {
  RuntimeMode,
  TrafficSample,
  TrafficChartPoint,
  ProxyNodeSnapshot,
  ProxyGroupSnapshot,
  ProxyDelayResult,
  ProxySelection,
  ProxyDelayOperationSnapshot,
  ConnectionSnapshot,
  DashboardSnapshot,
  FormattedBytes
} from '../model/RuntimeModels';

/** 合并同类在途请求；当前请求完成前的新调用共用 Promise，不额外排队。 */
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

/**
 * 以任务记录和节点归属跟踪并发测速；同一节点由最后发起的任务负责。
 * 进度事件与最终结果均调用 accept，确保一个结果只结算一次。
 */
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

  /** 返回本任务仍拥有但尚未完成的节点，供调用方在失败或超时后补齐状态。 */
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

  // 长度前缀消除分组名或节点名含冒号时的拼接歧义。
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

/** 按上传/下载比例生成圆环路径；先归一化再求比例，避免大总量相加溢出。 */
export function buildTrafficDonutPath(uploadTotal: number, downloadTotal: number,
  isUpload: boolean, size: number): string {
  const upload = Number.isFinite(uploadTotal) && uploadTotal > 0 ? uploadTotal : 0;
  const download = Number.isFinite(downloadTotal) && downloadTotal > 0 ? downloadTotal : 0;
  const maximum = Math.max(upload, download);
  if (maximum === 0 || !Number.isFinite(size) || size <= 0 || (isUpload ? upload : download) === 0) {
    return '';
  }
  const uploadRatio = (upload / maximum) / (upload / maximum + download / maximum);
  const gap = upload > 0 && download > 0 ? Math.PI / 10 : 0;
  const available = Math.PI * 2 - gap * 2;
  const start = -Math.PI / 2 + gap / 2 + (isUpload ? 0 : available * uploadRatio + gap);
  const sweep = available * (isUpload ? uploadRatio : 1 - uploadRatio);
  const center = size / 2;
  const radius = size * 0.4375;
  const middle = start + sweep / 2;
  const end = start + sweep;
  // Two arcs also draw the complete circle when only one direction has traffic.
  return `M ${center + radius * Math.cos(start)} ${center + radius * Math.sin(start)} ` +
    `A ${radius} ${radius} 0 0 1 ${center + radius * Math.cos(middle)} ${center + radius * Math.sin(middle)} ` +
    `A ${radius} ${radius} 0 0 1 ${center + radius * Math.cos(end)} ${center + radius * Math.sin(end)}`;
}

export function connectionTitle(connection: ConnectionSnapshot): string {
  if (connection.host.length > 0) {
    return connection.host;
  }
  return connection.destination;
}

/** 只累加有效代理采样区间的总量差，无基线时速率归零，计数器重置不产生负流量。 */
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

/** 固定映射最近一分钟，按本窗口峰值缩放纵轴，并限制切线避免平滑曲线越过真实峰谷。 */
export function buildTrafficChartPoints(history: TrafficSample[], width: number, height: number): TrafficChartPoint[] {
  if (history.length === 0 || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
    return [];
  }
  const earliestTimestamp = history[history.length - 1].timestamp - 60000;
  const maximum = history.reduce((peak: number, sample: TrafficSample): number =>
    Math.max(peak, sample.uploadSpeed + sample.downloadSpeed), 1);
  const points = history.map((sample: TrafficSample): TrafficChartPoint => ({
    x: Math.min(width, Math.max(0, sample.timestamp - earliestTimestamp) * width / 60000),
    y: height - (sample.uploadSpeed + sample.downloadSpeed) / maximum * Math.max(0, height - 12),
    slope: 0
  }));
  points.forEach((point: TrafficChartPoint, index: number): void => {
    const previous = points[Math.max(0, index - 1)];
    const next = points[Math.min(points.length - 1, index + 1)];
    const left = point.x > previous.x ? (point.y - previous.y) / (point.x - previous.x) : 0;
    const right = next.x > point.x ? (next.y - point.y) / (next.x - point.x) : 0;
    // Bound tangents by adjacent slopes to preserve the real peaks and valleys.
    point.slope = index === 0 ? right : (index === points.length - 1 ? left :
      (left * right <= 0 ? 0 : Math.sign(left) * Math.min(Math.abs(left), Math.abs(right))));
  });
  return points;
}

/** 只替换延迟状态发生变化的节点与分组，保留其余引用，减少 UI 无效重绘。 */
export function mergeGroupDelay(groups: ProxyGroupSnapshot[], groupName: string,
  results: ProxyDelayResult[]): ProxyGroupSnapshot[] {
  const resultByName = new Map<string, ProxyDelayResult>();
  results.forEach((result: ProxyDelayResult): void => {
    resultByName.set(result.proxy, result);
  });
  const merged = groups.map((group: ProxyGroupSnapshot): ProxyGroupSnapshot => {
    if (group.name !== groupName) {
      return group;
    }
    const nodes = group.nodes.map((node: ProxyNodeSnapshot): ProxyNodeSnapshot => {
      const result = resultByName.get(node.name);
      if (result === undefined || (node.tested && node.alive === result.alive && node.delay === result.delay)) {
        return node;
      }
      return {
        name: node.name, type: node.type, alive: result.alive,
        tested: true, delay: result.delay, udp: node.udp
      };
    });
    if (nodes.every((node: ProxyNodeSnapshot, index: number): boolean => node === group.nodes[index])) {
      return group;
    }
    return {
      name: group.name,
      type: group.type,
      selected: group.selected,
      selectable: group.selectable,
      hidden: group.hidden,
      nodes: nodes
    };
  });
  return merged.every((group: ProxyGroupSnapshot, index: number): boolean => group === groups[index]) ? groups : merged;
}

/** 轮询刷新保留已有手动测速结果，并复用字段相同的对象，避免节点列表抖动。 */
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
  const reconciled = merged.map((group: ProxyGroupSnapshot): ProxyGroupSnapshot => {
    const current = currentGroups.find((item: ProxyGroupSnapshot): boolean => item.name === group.name);
    if (current === undefined) {
      return group;
    }
    const currentNodes = new Map<string, ProxyNodeSnapshot>();
    current.nodes.forEach((node: ProxyNodeSnapshot): void => { currentNodes.set(node.name, node); });
    const nodes = group.nodes.map((node: ProxyNodeSnapshot): ProxyNodeSnapshot => {
      const previous = currentNodes.get(node.name);
      return previous !== undefined && previous.type === node.type && previous.alive === node.alive &&
        previous.tested === node.tested && previous.delay === node.delay && previous.udp === node.udp ? previous : node;
    });
    if (group.type === current.type && group.selected === current.selected && group.selectable === current.selectable &&
      group.hidden === current.hidden && nodes.length === current.nodes.length &&
      nodes.every((node: ProxyNodeSnapshot, index: number): boolean => node === current.nodes[index])) {
      return current;
    }
    return {
      name: group.name, type: group.type, selected: group.selected,
      selectable: group.selectable, hidden: group.hidden, nodes: nodes
    };
  });
  return reconciled.length === currentGroups.length &&
    reconciled.every((group: ProxyGroupSnapshot, index: number): boolean => group === currentGroups[index]) ?
    currentGroups : reconciled;
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
    return '测速中';
  }
  if (!node.tested) {
    return '未测速';
  }
  return node.alive && node.delay > 0 ? `${node.delay} ms` : '超时';
}

/** 匹配组名时展示整组，否则只展示名称或协议匹配的节点。 */
export function filterProxyNodes(group: ProxyGroupSnapshot, query: string): ProxyNodeSnapshot[] {
  const keyword = query.trim().toLocaleLowerCase();
  if (keyword.length === 0 || group.name.toLocaleLowerCase().includes(keyword)) {
    return group.nodes;
  }
  return group.nodes.filter((node: ProxyNodeSnapshot): boolean =>
    node.name.toLocaleLowerCase().includes(keyword) || node.type.toLocaleLowerCase().includes(keyword));
}

export function proxyNodeRenderKey(node: ProxyNodeSnapshot): string {
  return `${node.name.length}:${node.name}`;
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

/** 优先恢复仍可见的保存分组，全局模式回退 GLOBAL，否则使用首个可见分组。 */
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
