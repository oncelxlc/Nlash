import { Profile, ProfileStoreSnapshot } from '../models/ProfileModels';
import {
  appendTrafficSample,
  ConnectionSnapshot,
  ConnectionsSnapshot,
  DashboardSnapshot,
  GroupDelayResult,
  mergeGroupDelay,
  ProxyGroupSnapshot,
  ProxySelection,
  ProxySnapshot,
  ProxySnapshotSource,
  pruneProxySelections,
  RequestRecord,
  RuntimeCommandResponse,
  RuntimeMode,
  RuntimeStoreListener,
  RuntimeStoreSnapshot,
  TrafficSample
} from '../models/RuntimeModels';
import { VpnState } from '../models/VpnModels';
import { feedbackService } from '../services/FeedbackService';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { profilePreviewService } from '../services/ProfilePreviewService';
import { runtimeControlService } from '../services/RuntimeControlService';
import { vpnService } from '../services/VpnService';
import { profileStore } from './ProfileStore';

const POLL_INTERVAL_MS = 1000;
const MAX_REQUEST_HISTORY = 200;

interface SelectProxyCommandPayload { group: string; proxy: string; }
interface GroupDelayCommandPayload { group: string; proxy: string; url: string; timeout: number; }
interface CloseConnectionCommandPayload { id: string; }
interface SetModeCommandPayload { mode: RuntimeMode; }

class RuntimeStore {
  private available: boolean = false;
  private refreshing: boolean = false;
  private previewLoading: boolean = false;
  private dashboard: DashboardSnapshot | undefined;
  private proxies: ProxyGroupSnapshot[] = [];
  private proxySource: ProxySnapshotSource = ProxySnapshotSource.NONE;
  private proxySelections: ProxySelection[] = [];
  private trafficHistory: TrafficSample[] = [];
  private connections: ConnectionSnapshot[] = [];
  private requests: RequestRecord[] = [];
  private busyKey: string = '';
  private lastBackgroundError: string = '';
  private listeners: Set<RuntimeStoreListener> = new Set<RuntimeStoreListener>();
  private pollTimer: number | undefined;
  private vpnUnsubscribe: (() => void) | undefined;
  private profileUnsubscribe: (() => void) | undefined;
  private refreshOperation: Promise<void> | undefined;
  private pollCount: number = 0;
  private profileId: string = '';
  private configPath: string = '';
  private profileSignature: string = '';
  private previewGeneration: number = 0;

  initialize(): void {
    if (this.vpnUnsubscribe !== undefined) {
      return;
    }
    runtimeControlService.initialize().catch((): void => {
      this.reportBackgroundError('Core 控制通道初始化失败');
    });
    this.profileUnsubscribe = profileStore.subscribe((snapshot: ProfileStoreSnapshot): void => {
      this.handleProfileSnapshot(snapshot);
    });
    this.vpnUnsubscribe = vpnService.subscribe((state: VpnState): void => {
      if (state === VpnState.CONNECTED) {
        const wasAvailable = this.available;
        this.available = true;
        if (!wasAvailable) {
          this.trafficHistory = [];
        }
        this.startPolling();
        this.refresh();
      } else if (state === VpnState.IDLE || state === VpnState.DISCONNECTED || state === VpnState.ERROR) {
        this.available = false;
        this.stopPolling();
        this.finishActiveRequests();
        this.dashboard = undefined;
        this.connections = [];
        this.busyKey = '';
        this.publish();
        this.loadPreview();
      }
    });
  }

  getSnapshot(): RuntimeStoreSnapshot {
    return {
      available: this.available,
      refreshing: this.refreshing,
      previewLoading: this.previewLoading,
      dashboard: this.dashboard,
      proxies: this.proxies.slice(),
      proxySource: this.proxySource,
      proxySelections: this.proxySelections.slice(),
      trafficHistory: this.trafficHistory.slice(),
      connections: this.connections.slice(),
      requests: this.requests.slice(),
      busyKey: this.busyKey
    };
  }

  subscribe(listener: RuntimeStoreListener): () => void {
    this.listeners.add(listener);
    listener(this.getSnapshot());
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  refresh(): Promise<void> {
    if (!this.available) {
      return this.loadPreview();
    }
    if (this.refreshOperation === undefined) {
      const operation = this.refreshInternal();
      this.refreshOperation = operation;
      operation.then((): void => { this.refreshOperation = undefined; },
        (): void => { this.refreshOperation = undefined; });
    }
    return this.refreshOperation;
  }

  async selectProxy(group: string, proxy: string): Promise<void> {
    if (this.profileId.length === 0) {
      throw new Error('请先选择活动配置');
    }
    await this.runAction(`select:${group}`, async (): Promise<void> => {
      this.requireSelectableNode(group, proxy);
      if (this.available) {
        const payload: SelectProxyCommandPayload = { group: group, proxy: proxy };
        this.requireOK<Object>(await runtimeControlService.execute<Object>('selectProxy', payload));
        await this.refreshProxies();
      }
      await preferenceRepository.setProxySelection(this.profileId, group, proxy);
      this.proxySelections = this.replaceSelection(this.proxySelections, group, proxy);
    });
  }

  async testDelay(group: string, proxy: string, testUrl: string): Promise<number> {
    let delay = -1;
    await this.runAction(`delay:${proxy}`, async (): Promise<void> => {
      const result = await this.executeGroupDelay(group, proxy, testUrl);
      this.proxies = mergeGroupDelay(this.proxies, group, result.results);
      const nodeResult = result.results.find((item): boolean => item.proxy === proxy);
      delay = nodeResult?.delay ?? -1;
    });
    return delay;
  }

  async testGroupDelay(group: string, testUrl: string): Promise<void> {
    await this.runAction(`delay-group:${group}`, async (): Promise<void> => {
      const result = await this.executeGroupDelay(group, '', testUrl);
      this.proxies = mergeGroupDelay(this.proxies, group, result.results);
    });
  }

  async closeConnection(id: string): Promise<void> {
    this.requireRuntime();
    await this.runAction(`connection:${id}`, async (): Promise<void> => {
      const payload: CloseConnectionCommandPayload = { id: id };
      this.requireOK<Object>(await runtimeControlService.execute<Object>('closeConnection', payload));
      await this.refreshConnections();
    });
  }

  async closeAllConnections(): Promise<void> {
    this.requireRuntime();
    await this.runAction('connections:all', async (): Promise<void> => {
      this.requireOK<Object>(await runtimeControlService.execute<Object>('closeAllConnections'));
      await this.refreshConnections();
    });
  }

  async setMode(mode: RuntimeMode): Promise<void> {
    this.requireRuntime();
    await this.runAction('mode', async (): Promise<void> => {
      const payload: SetModeCommandPayload = { mode: mode };
      this.requireOK<Object>(await runtimeControlService.execute<Object>('setMode', payload));
      await this.refreshDashboard();
    });
  }

  async resetTraffic(): Promise<void> {
    this.requireRuntime();
    await this.runAction('traffic', async (): Promise<void> => {
      this.requireOK<Object>(await runtimeControlService.execute<Object>('resetTraffic'));
      await this.refreshDashboard();
    });
  }

  clearRequests(): void {
    this.requests = [];
    this.publish();
  }

  private handleProfileSnapshot(snapshot: ProfileStoreSnapshot): void {
    const active = snapshot.profiles.find((profile: Profile): boolean => profile.id === snapshot.activeProfileId);
    const signature = active === undefined ? '' : `${active.id}:${active.localPath}:${active.updatedAt}`;
    if (signature === this.profileSignature) {
      return;
    }
    this.profileSignature = signature;
    this.profileId = active?.id ?? '';
    this.configPath = active?.localPath ?? '';
    this.previewGeneration += 1;
    if (!this.available) {
      this.proxies = [];
      this.proxySource = ProxySnapshotSource.NONE;
    }
    this.loadSelectionsAndPreview(this.previewGeneration);
  }

  private async loadSelectionsAndPreview(generation: number): Promise<void> {
    if (this.profileId.length === 0 || this.configPath.length === 0) {
      this.proxySelections = [];
      this.previewLoading = false;
      this.publish();
      return;
    }
    const profileId = this.profileId;
    try {
      const selections = await preferenceRepository.getProxySelections(profileId);
      if (generation !== this.previewGeneration || profileId !== this.profileId) {
        return;
      }
      this.proxySelections = selections;
      this.publish();
      if (!this.available) {
        await this.loadPreview(generation);
      }
    } catch (error) {
      if (generation === this.previewGeneration) {
        this.reportBackgroundError(this.errorMessage(error));
      }
    }
  }

  private async loadPreview(expectedGeneration: number = this.previewGeneration): Promise<void> {
    if (this.available || this.configPath.length === 0) {
      return;
    }
    const configPath = this.configPath;
    const profileId = this.profileId;
    this.previewLoading = true;
    this.publish();
    try {
      const snapshot = await profilePreviewService.load(configPath);
      if (expectedGeneration !== this.previewGeneration || this.available ||
        configPath !== this.configPath || profileId !== this.profileId) {
        return;
      }
      this.proxies = snapshot.groups;
      this.proxySource = ProxySnapshotSource.CONFIG;
      const validSelections = pruneProxySelections(this.proxies, this.proxySelections);
      if (validSelections.length !== this.proxySelections.length) {
        this.proxySelections = validSelections;
        await preferenceRepository.replaceProxySelections(profileId, validSelections);
      }
      this.clearBackgroundError();
    } catch (error) {
      if (expectedGeneration === this.previewGeneration && !this.available) {
        this.proxies = [];
        this.proxySource = ProxySnapshotSource.NONE;
        this.reportBackgroundError(this.errorMessage(error));
      }
    } finally {
      if (expectedGeneration === this.previewGeneration) {
        this.previewLoading = false;
        this.publish();
      }
    }
  }

  private async executeGroupDelay(group: string, proxy: string, testUrl: string): Promise<GroupDelayResult> {
    if (this.available) {
      const payload: GroupDelayCommandPayload = {
        group: group, proxy: proxy, url: testUrl, timeout: 5000
      };
      return this.requireSuccess<GroupDelayResult>(
        await runtimeControlService.execute<GroupDelayResult>('testGroupDelay', payload));
    }
    if (this.configPath.length === 0) {
      throw new Error('请先选择活动配置');
    }
    return profilePreviewService.testGroup(this.configPath, group, proxy, testUrl);
  }

  private async refreshInternal(): Promise<void> {
    this.refreshing = true;
    this.publish();
    try {
      await this.refreshDashboard();
      await this.refreshConnections();
      this.pollCount += 1;
      if (this.proxies.length === 0 || this.pollCount % 5 === 0) {
        await this.refreshProxies();
      }
      this.clearBackgroundError();
    } catch (error) {
      this.reportBackgroundError(this.errorMessage(error));
    } finally {
      this.refreshing = false;
      this.publish();
    }
  }

  private async refreshDashboard(): Promise<void> {
    const response = await runtimeControlService.execute<DashboardSnapshot>('dashboardSnapshot');
    this.dashboard = this.requireSuccess<DashboardSnapshot>(response);
    this.trafficHistory = appendTrafficSample(this.trafficHistory, {
      timestamp: Date.now(),
      uploadSpeed: this.dashboard.uploadSpeed,
      downloadSpeed: this.dashboard.downloadSpeed
    });
  }

  private async refreshProxies(): Promise<void> {
    const response = await runtimeControlService.execute<ProxySnapshot>('proxySnapshot');
    this.proxies = this.requireSuccess<ProxySnapshot>(response).groups;
    this.proxySource = ProxySnapshotSource.RUNTIME;
  }

  private async refreshConnections(): Promise<void> {
    const response = await runtimeControlService.execute<ConnectionsSnapshot>('connectionSnapshot');
    const snapshot = this.requireSuccess<ConnectionsSnapshot>(response);
    this.mergeRequestHistory(snapshot.connections);
    this.connections = snapshot.connections;
  }

  private mergeRequestHistory(current: ConnectionSnapshot[]): void {
    const now = Date.now();
    const previousById = new Map<string, RequestRecord>();
    this.requests.forEach((record: RequestRecord): void => {
      previousById.set(record.id, record);
    });
    const merged: RequestRecord[] = [];
    current.forEach((connection: ConnectionSnapshot): void => {
      merged.push(this.toRequestRecord(connection, true, 0));
      previousById.delete(connection.id);
    });
    previousById.forEach((record: RequestRecord): void => {
      merged.push({
        id: record.id, network: record.network, host: record.host,
        destination: record.destination, process: record.process, start: record.start,
        end: record.active ? now : record.end, upload: record.upload, download: record.download,
        chains: record.chains.slice(), rule: record.rule, rulePayload: record.rulePayload, active: false
      });
    });
    merged.sort((left: RequestRecord, right: RequestRecord): number => right.start - left.start);
    this.requests = merged.slice(0, MAX_REQUEST_HISTORY);
  }

  private toRequestRecord(connection: ConnectionSnapshot, active: boolean, end: number): RequestRecord {
    return {
      id: connection.id, network: connection.network, host: connection.host,
      destination: connection.destination, process: connection.process, start: connection.start,
      end: end, upload: connection.upload, download: connection.download,
      chains: connection.chains.slice(), rule: connection.rule,
      rulePayload: connection.rulePayload, active: active
    };
  }

  private finishActiveRequests(): void {
    const now = Date.now();
    this.requests = this.requests.map((record: RequestRecord): RequestRecord => record.active ? {
      id: record.id, network: record.network, host: record.host, destination: record.destination,
      process: record.process, start: record.start, end: now, upload: record.upload,
      download: record.download, chains: record.chains.slice(), rule: record.rule,
      rulePayload: record.rulePayload, active: false
    } : record);
  }

  private async runAction(key: string, action: () => Promise<void>): Promise<void> {
    if (this.busyKey.length > 0) {
      throw new Error('已有 Core 操作正在执行');
    }
    this.busyKey = key;
    this.publish();
    try {
      await action();
    } catch (error) {
      throw new Error(this.errorMessage(error));
    } finally {
      this.busyKey = '';
      this.publish();
    }
  }

  private requireRuntime(): void {
    if (!this.available) {
      throw new Error('请先连接 VPN');
    }
  }

  private requireSelectableNode(groupName: string, proxy: string): void {
    const group = this.proxies.find((item: ProxyGroupSnapshot): boolean => item.name === groupName);
    if (group === undefined || !group.selectable ||
      !group.nodes.some((node): boolean => node.name === proxy)) {
      throw new Error('代理组或节点已失效');
    }
  }

  private replaceSelection(current: ProxySelection[], group: string, proxy: string): ProxySelection[] {
    const next = current.filter((selection: ProxySelection): boolean => selection.group !== group);
    next.push({ group: group, proxy: proxy });
    return next;
  }

  private requireSuccess<T>(response: RuntimeCommandResponse<T>): T {
    if (!response.ok || response.data === undefined) {
      throw new Error(response.message.length > 0 ? response.message : response.code);
    }
    return response.data;
  }

  private requireOK<T>(response: RuntimeCommandResponse<T>): void {
    if (!response.ok) {
      throw new Error(response.message.length > 0 ? response.message : response.code);
    }
  }

  private startPolling(): void {
    if (this.pollTimer === undefined) {
      this.pollTimer = setInterval((): void => { this.refresh(); }, POLL_INTERVAL_MS);
    }
  }

  private stopPolling(): void {
    if (this.pollTimer !== undefined) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  private publish(): void {
    const snapshot = this.getSnapshot();
    this.listeners.forEach((listener: RuntimeStoreListener): void => listener(snapshot));
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : 'Core 操作失败';
  }

  private reportBackgroundError(message: string): void {
    if (message === this.lastBackgroundError) {
      return;
    }
    this.lastBackgroundError = message;
    feedbackService.error(message);
  }

  private clearBackgroundError(): void {
    this.lastBackgroundError = '';
  }
}

export const runtimeStore = new RuntimeStore();
