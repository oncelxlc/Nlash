import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProxyDelayProgress, ProxyDelayProgressListener } from '../models/CoreControlProtocol';
import { Profile, ProfileStoreSnapshot } from '../models/ProfileModels';
import {
  appendTrafficSample,
  ConnectionSnapshot,
  ConnectionsSnapshot,
  DashboardSnapshot,
  failPendingGroupDelay,
  GroupDelayResult,
  mergeGroupDelay,
  ProxyGroupSnapshot,
  ProxySelection,
  ProxySnapshot,
  ProxySnapshotSource,
  preserveTestedProxyDelays,
  pruneProxySelections,
  RequestRecord,
  resetGroupDelay,
  RuntimeCommandResponse,
  RuntimeMode,
  RuntimeRequestMerger,
  RuntimeStoreListener,
  RuntimeStoreSnapshot,
  TrafficSample
} from '../models/RuntimeModels';
import {
  AppSettings,
  resolveRefreshIntervalMilliseconds,
  SettingsStoreSnapshot
} from '../models/SettingsModels';
import { CoreServiceState, RuntimeLifecycleSnapshot } from '../models/VpnModels';
import { feedbackService } from '../services/FeedbackService';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { profilePreviewService } from '../services/ProfilePreviewService';
import { runtimeControlService } from '../services/RuntimeControlService';
import { vpnService } from '../services/VpnService';
import { profileStore } from './ProfileStore';
import { settingsStore } from './SettingsStore';

const MAX_REQUEST_HISTORY = 200;
const DELAY_TEST_TIMEOUT_MS = 10000;
const DELAY_TEST_CONCURRENCY = 8;
const DELAY_COMMAND_MARGIN_MS = 7000;
const MIN_DELAY_COMMAND_TIMEOUT_MS = 12000;
const DELAY_LOG_DOMAIN = 0xD001;
const DELAY_LOG_TAG = 'NlashDelay';

interface SelectProxyCommandPayload { group: string; proxy: string; }
interface GroupDelayCommandPayload {
  group: string;
  proxy: string;
  url: string;
  timeout: number;
  operationId: string;
}
interface CloseConnectionCommandPayload { id: string; }
interface SetModeCommandPayload { mode: RuntimeMode; }

class RuntimeStore {
  private coreAvailable: boolean = false;
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
  private lifecycleUnsubscribe: (() => void) | undefined;
  private profileUnsubscribe: (() => void) | undefined;
  private settingsUnsubscribe: (() => void) | undefined;
  private refreshMerger: RuntimeRequestMerger = new RuntimeRequestMerger();
  private refreshIntervalMs: number = 3000;
  private profileId: string = '';
  private configPath: string = '';
  private profileSignature: string = '';
  private previewGeneration: number = 0;
  private activeDelayOperationId: string = '';
  private activeDelayGroup: string = '';
  private activeDelayGeneration: number = 0;
  private activeDelayProfileSignature: string = '';
  private activeDelayRuntime: boolean = false;
  private runtimeUsesConfigIndex: boolean = false;
  private foreground: boolean = true;
  private lifecycleGeneration: number = 0;

  initialize(): void {
    if (this.lifecycleUnsubscribe !== undefined) {
      return;
    }
    runtimeControlService.initialize().catch((): void => {
      this.reportBackgroundError('Core 控制通道初始化失败');
    });
    this.profileUnsubscribe = profileStore.subscribe((snapshot: ProfileStoreSnapshot): void => {
      this.handleProfileSnapshot(snapshot);
    });
    this.settingsUnsubscribe = settingsStore.subscribe((snapshot: SettingsStoreSnapshot): void => {
      this.handleSettingsSnapshot(snapshot.settings);
    });
    this.lifecycleUnsubscribe = vpnService.subscribeLifecycle((snapshot: RuntimeLifecycleSnapshot): void => {
      const available = snapshot.coreState === CoreServiceState.RUNNING;
      if (available) {
        const wasAvailable = this.coreAvailable;
        this.coreAvailable = true;
        if (!wasAvailable) {
          this.trafficHistory = [];
          this.invalidateDelayOperation();
          if (this.isDelayBusy()) {
            this.busyKey = '';
          }
          this.runtimeUsesConfigIndex = false;
          this.applyPreselectedSelections();
        }
        if (this.foreground) {
          this.startPolling();
          this.refresh();
        }
      } else {
        if (!this.coreAvailable) {
          return;
        }
        this.coreAvailable = false;
        this.runtimeUsesConfigIndex = false;
        const cancelDelay = this.activeDelayOperationId.length === 0 || this.activeDelayRuntime;
        if (cancelDelay) {
          this.invalidateDelayOperation();
        }
        this.stopPolling();
        this.finishActiveRequests();
        this.dashboard = undefined;
        this.connections = [];
        if (cancelDelay) {
          this.busyKey = '';
        }
        this.publish();
        this.loadPreview();
      }
    });
  }

  setForeground(foreground: boolean): void {
    if (this.foreground === foreground) {
      return;
    }
    this.foreground = foreground;
    this.lifecycleGeneration += 1;
    if (!foreground) {
      this.stopPolling();
      return;
    }
    if (this.coreAvailable) {
      this.startPolling();
      this.refresh();
    }
  }

  getSnapshot(): RuntimeStoreSnapshot {
    return {
      coreAvailable: this.coreAvailable,
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
    if (!this.coreAvailable) {
      if (this.previewLoading || (this.proxySource === ProxySnapshotSource.CONFIG && this.proxies.length > 0)) {
        return Promise.resolve();
      }
      return this.loadPreview();
    }
    return this.refreshMerger.run((): Promise<void> => this.refreshInternal());
  }

  async selectProxy(group: string, proxy: string): Promise<void> {
    if (this.profileId.length === 0) {
      throw new Error('请先选择活动配置');
    }
    await this.runAction(`select:${group}`, async (): Promise<void> => {
      this.requireSelectableNode(group, proxy);
      const originalGroups = this.proxies;
      const originalSelections = this.proxySelections;
      const originalGroup = originalGroups.find((item: ProxyGroupSnapshot): boolean => item.name === group);
      const originalProxy = originalGroup?.selected ?? '';
      let runtimeChanged = false;
      if (this.coreAvailable) {
        const payload: SelectProxyCommandPayload = { group: group, proxy: proxy };
        this.requireOK<Object>(await runtimeControlService.execute<Object>('selectProxy', payload));
        runtimeChanged = true;
        this.proxies = this.replaceRuntimeSelection(this.proxies, group, proxy);
        this.proxySelections = this.replaceSelection(this.proxySelections, group, proxy);
        this.publish();
      }
      try {
        await preferenceRepository.setProxySelection(this.profileId, group, proxy);
      } catch (error) {
        let runtimeRollbackFailed = false;
        try {
          await preferenceRepository.replaceProxySelections(this.profileId, originalSelections);
        } catch (rollbackError) {
          // The original in-memory selection remains authoritative for this session.
        }
        if (runtimeChanged && originalProxy.length > 0 && originalProxy !== proxy) {
          try {
            const rollbackPayload: SelectProxyCommandPayload = { group: group, proxy: originalProxy };
            this.requireOK<Object>(await runtimeControlService.execute<Object>('selectProxy', rollbackPayload));
          } catch (rollbackError) {
            runtimeRollbackFailed = true;
          }
        }
        this.proxies = originalGroups;
        this.proxySelections = originalSelections;
        this.publish();
        throw new Error(runtimeRollbackFailed ?
          '节点选择保存失败，且 Core 节点恢复失败' : '节点选择保存失败，已恢复原节点');
      }
      this.proxySelections = this.replaceSelection(this.proxySelections, group, proxy);
    });
  }

  commitDelayResult(group: string, proxy: string, delay: number): void {
    this.proxies = mergeGroupDelay(this.proxies, group, [{
      proxy: proxy,
      delay: delay,
      alive: delay > 0
    }]);
    this.publish();
  }

  completePendingDelayResults(group: string): void {
    this.proxies = failPendingGroupDelay(this.proxies, group);
    this.publish();
  }

  async testDelay(group: string, proxy: string, testUrl: string): Promise<number> {
    if (this.busyKey.length > 0) {
      throw new Error('已有 Core 操作正在执行');
    }
    let delay = -1;
    const generation = this.previewGeneration;
    const profileSignature = this.profileSignature;
    const startedProfileId = this.profileId;
    const startedConfigPath = this.configPath;
    const startedInRuntime = this.coreAvailable && this.proxySource === ProxySnapshotSource.RUNTIME;
    const actionKey = `delay:${group}:${proxy}`;
    const operationId = util.generateRandomUUID();
    this.activeDelayOperationId = operationId;
    this.activeDelayGroup = group;
    this.activeDelayGeneration = generation;
    this.activeDelayProfileSignature = profileSignature;
    this.activeDelayRuntime = startedInRuntime;
    this.busyKey = actionKey;
    this.proxies = resetGroupDelay(this.proxies, group, proxy);
    this.publish();
    hilog.info(DELAY_LOG_DOMAIN, DELAY_LOG_TAG,
      'start operation=%{public}s mode=%{public}s generation=%{public}d',
      operationId.substring(0, 8), startedInRuntime ? 'runtime' : 'preview', generation);
    const progressListener: ProxyDelayProgressListener = (progress: ProxyDelayProgress): void => {
      this.applyDelayProgress(progress);
    };
    try {
      const result = await this.executeGroupDelay(group, proxy, testUrl, operationId, 1, startedInRuntime,
        progressListener);
      if (!this.canApplyDelayResult(operationId, group, generation, profileSignature, startedInRuntime,
        startedProfileId, startedConfigPath)) {
        return delay;
      }
      const nodeResult = result.results.find((item): boolean => item.proxy === proxy);
      this.proxies = mergeGroupDelay(this.proxies, group, result.results);
      this.proxies = failPendingGroupDelay(this.proxies, group, proxy);
      const storedGroup = this.proxies.find((item: ProxyGroupSnapshot): boolean => item.name === group);
      const storedNode = storedGroup?.nodes.find((item): boolean => item.name === proxy);
      hilog.info(DELAY_LOG_DOMAIN, DELAY_LOG_TAG,
        'final operation=%{public}s results=%{public}d returnedMatch=%{public}d storedMatch=%{public}d ' +
        'tested=%{public}d delay=%{public}d', operationId.substring(0, 8), result.results.length,
        nodeResult === undefined ? 0 : 1, storedNode === undefined ? 0 : 1, storedNode?.tested ? 1 : 0,
        storedNode?.delay ?? -1);
      delay = nodeResult?.delay ?? -1;
    } catch (error) {
      if (!this.canApplyDelayResult(operationId, group, generation, profileSignature, startedInRuntime,
        startedProfileId, startedConfigPath)) {
        return delay;
      }
      this.proxies = failPendingGroupDelay(this.proxies, group, proxy);
      throw new Error(this.errorMessage(error));
    } finally {
      if (this.activeDelayOperationId === operationId) {
        this.invalidateDelayOperation();
        if (this.busyKey === actionKey) {
          this.busyKey = '';
        }
        this.publish();
      }
    }
    return delay;
  }

  async testGroupDelay(group: string, testUrl: string): Promise<void> {
    if (this.busyKey.length > 0) {
      throw new Error('已有 Core 操作正在执行');
    }
    const targetGroup = this.proxies.find((item: ProxyGroupSnapshot): boolean => item.name === group);
    if (targetGroup === undefined || targetGroup.nodes.length === 0) {
      throw new Error('当前代理组没有可测试节点');
    }
    const operationId = util.generateRandomUUID();
    const generation = this.previewGeneration;
    const profileSignature = this.profileSignature;
    const startedProfileId = this.profileId;
    const startedConfigPath = this.configPath;
    const startedInRuntime = this.coreAvailable && this.proxySource === ProxySnapshotSource.RUNTIME;
    this.activeDelayOperationId = operationId;
    this.activeDelayGroup = group;
    this.activeDelayGeneration = generation;
    this.activeDelayProfileSignature = profileSignature;
    this.activeDelayRuntime = startedInRuntime;
    this.busyKey = `delay-group:${group}`;
    this.proxies = resetGroupDelay(this.proxies, group);
    this.publish();
    const progressListener: ProxyDelayProgressListener = (progress: ProxyDelayProgress): void => {
      if (this.isActiveDelayOperation(progress.operationId, progress.group, generation, profileSignature)) {
        this.applyDelayProgress(progress);
      } else if (!startedInRuntime && !this.coreAvailable &&
        this.isPreviewProfileCurrent(startedProfileId, startedConfigPath) &&
        progress.operationId === operationId && progress.group === group) {
        this.proxies = mergeGroupDelay(this.proxies, group, [{
          proxy: progress.proxy,
          delay: progress.delay,
          alive: progress.alive,
          errorCode: progress.errorCode
        }]);
        this.publish();
      }
    };
    try {
      const result = await this.executeGroupDelay(group, '', testUrl, operationId,
        targetGroup.nodes.length, startedInRuntime, progressListener);
      if (this.canApplyDelayResult(operationId, group, generation, profileSignature, startedInRuntime,
        startedProfileId, startedConfigPath)) {
        this.proxies = mergeGroupDelay(this.proxies, group, result.results);
        this.proxies = failPendingGroupDelay(this.proxies, group);
        this.publish();
      }
    } catch (error) {
      if (!this.canApplyDelayResult(operationId, group, generation, profileSignature, startedInRuntime,
        startedProfileId, startedConfigPath)) {
        return;
      }
      this.proxies = failPendingGroupDelay(this.proxies, group);
      this.publish();
      throw new Error(this.errorMessage(error));
    } finally {
      if (this.activeDelayOperationId === operationId) {
        this.invalidateDelayOperation();
        if (this.busyKey === `delay-group:${group}`) {
          this.busyKey = '';
        }
        this.publish();
      }
    }
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
    this.invalidateDelayOperation();
    if (this.isDelayBusy()) {
      this.busyKey = '';
    }
    this.profileSignature = signature;
    this.profileId = active?.id ?? '';
    this.configPath = active?.localPath ?? '';
    this.previewGeneration += 1;
    if (!this.coreAvailable) {
      this.proxies = [];
      this.proxySource = ProxySnapshotSource.NONE;
    }
    this.loadSelectionsAndPreview(this.previewGeneration);
  }

  private handleSettingsSnapshot(settings: AppSettings): void {
    const nextIntervalMs = resolveRefreshIntervalMilliseconds(settings.refreshIntervalSeconds);
    if (nextIntervalMs === this.refreshIntervalMs) {
      return;
    }
    this.refreshIntervalMs = nextIntervalMs;
    this.lifecycleGeneration += 1;
    this.stopPolling();
    if (this.foreground && this.coreAvailable) {
      this.refresh();
      this.startPolling();
    }
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
      if (!this.coreAvailable) {
        await this.loadPreview(generation);
      }
    } catch (error) {
      if (generation === this.previewGeneration) {
        this.reportBackgroundError(this.errorMessage(error));
      }
    }
  }

  private async loadPreview(expectedGeneration: number = this.previewGeneration): Promise<void> {
    if (this.coreAvailable || this.configPath.length === 0) {
      return;
    }
    const configPath = this.configPath;
    const profileId = this.profileId;
    this.previewLoading = true;
    this.publish();
    try {
      const snapshot = await profilePreviewService.load(configPath);
      if (expectedGeneration !== this.previewGeneration || this.coreAvailable ||
        configPath !== this.configPath || profileId !== this.profileId) {
        return;
      }
      this.proxies = preserveTestedProxyDelays(snapshot.groups, this.proxies);
      this.proxySource = ProxySnapshotSource.CONFIG;
      const validSelections = pruneProxySelections(this.proxies, this.proxySelections);
      if (validSelections.length !== this.proxySelections.length) {
        this.proxySelections = validSelections;
        await preferenceRepository.replaceProxySelections(profileId, validSelections);
      }
      this.clearBackgroundError();
    } catch (error) {
      if (expectedGeneration === this.previewGeneration && !this.coreAvailable) {
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

  private async executeGroupDelay(group: string, proxy: string, testUrl: string,
    operationId: string, nodeCount: number, useRuntime: boolean,
    progressListener: ProxyDelayProgressListener | undefined = undefined): Promise<GroupDelayResult> {
    if (useRuntime) {
      await runtimeControlService.initialize();
      const payload: GroupDelayCommandPayload = {
        group: group, proxy: proxy, url: testUrl, timeout: DELAY_TEST_TIMEOUT_MS,
        operationId: operationId
      };
      const unsubscribe = progressListener === undefined ? undefined :
        runtimeControlService.subscribeDelayProgress(progressListener);
      try {
        return this.requireSuccess<GroupDelayResult>(
          await runtimeControlService.execute<GroupDelayResult>('testGroupDelay', payload,
            this.delayCommandTimeout(nodeCount)));
      } finally {
        unsubscribe?.();
      }
    }
    if (this.configPath.length === 0) {
      throw new Error('请先选择活动配置');
    }
    return this.withTimeout(profilePreviewService.testGroup(this.configPath, group, proxy, testUrl,
      operationId, progressListener), this.delayCommandTimeout(nodeCount), '预览延迟检测超时');
  }

  private async refreshInternal(): Promise<void> {
    const lifecycleGeneration = this.lifecycleGeneration;
    this.refreshing = true;
    this.publish();
    try {
      await this.refreshDashboard();
      this.publish();
      if (!this.isDelayBusy()) {
        await this.refreshProxies();
        this.publish();
      }
      await this.refreshConnections();
      this.clearBackgroundError();
    } catch (error) {
      if (this.foreground && lifecycleGeneration === this.lifecycleGeneration) {
        this.reportBackgroundError(this.errorMessage(error));
      }
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

  private applyPreselectedSelections(): void {
    runtimeControlService.execute<Object>('applyProxySelections').then(
      (response: RuntimeCommandResponse<Object>): void => {
        if (!response.ok) {
          this.reportBackgroundError(response.message.length > 0 ? response.message : response.code);
        }
      }, (error: Error): void => {
        this.reportBackgroundError(this.errorMessage(error));
      });
  }

  private async refreshProxies(): Promise<void> {
    const response = await runtimeControlService.execute<ProxySnapshot>('proxySnapshot');
    const freshGroups = this.requireSuccess<ProxySnapshot>(response).groups;
    this.proxies = preserveTestedProxyDelays(freshGroups, this.proxies);
    this.proxySource = ProxySnapshotSource.RUNTIME;
    this.runtimeUsesConfigIndex = false;
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
      if (this.busyKey === key) {
        this.busyKey = '';
        this.publish();
      }
    }
  }

  private applyDelayProgress(progress: ProxyDelayProgress): void {
    if (!this.isActiveDelayOperation(progress.operationId, progress.group,
      this.activeDelayGeneration, this.activeDelayProfileSignature)) {
      return;
    }
    this.proxies = mergeGroupDelay(this.proxies, progress.group, [{
      proxy: progress.proxy,
      delay: progress.delay,
      alive: progress.alive,
      errorCode: progress.errorCode
    }]);
    this.publish();
  }

  private isActiveDelayOperation(operationId: string, group: string, generation: number,
    profileSignature: string): boolean {
    return this.activeDelayOperationId === operationId && this.activeDelayGroup === group &&
      this.activeDelayGeneration === generation && this.activeDelayProfileSignature === profileSignature &&
      this.isDelayContextCurrent(generation, profileSignature);
  }

  private isDelayContextCurrent(generation: number, profileSignature: string): boolean {
    return this.previewGeneration === generation && this.profileSignature === profileSignature;
  }

  private canApplyDelayResult(operationId: string, group: string, generation: number,
    profileSignature: string, startedInRuntime: boolean, startedProfileId: string,
    startedConfigPath: string): boolean {
    return this.isActiveDelayOperation(operationId, group, generation, profileSignature) ||
      (!startedInRuntime && !this.coreAvailable &&
        this.isPreviewProfileCurrent(startedProfileId, startedConfigPath));
  }

  private isPreviewProfileCurrent(profileId: string, configPath: string): boolean {
    return profileId.length > 0 && profileId === this.profileId && configPath === this.configPath;
  }

  private invalidateDelayOperation(): void {
    this.activeDelayOperationId = '';
    this.activeDelayGroup = '';
    this.activeDelayGeneration = 0;
    this.activeDelayProfileSignature = '';
    this.activeDelayRuntime = false;
  }

  private isDelayBusy(): boolean {
    return this.busyKey.startsWith('delay:') || this.busyKey.startsWith('delay-group:');
  }

  private delayCommandTimeout(nodeCount: number): number {
    const rounds = Math.ceil(Math.max(1, nodeCount) / DELAY_TEST_CONCURRENCY);
    return Math.max(MIN_DELAY_COMMAND_TIMEOUT_MS,
      rounds * DELAY_TEST_TIMEOUT_MS + DELAY_COMMAND_MARGIN_MS);
  }

  private async withTimeout<T>(operation: Promise<T>, timeoutMs: number, message: string): Promise<T> {
    let timeoutId = -1;
    const timeout = new Promise<T>((_resolve: (value: T) => void, reject: (reason: Error) => void): void => {
      timeoutId = setTimeout((): void => reject(new Error(message)), timeoutMs);
    });
    try {
      return await Promise.race([operation, timeout]);
    } finally {
      if (timeoutId >= 0) {
        clearTimeout(timeoutId);
      }
    }
  }

  private requireRuntime(): void {
    if (!this.coreAvailable) {
      throw new Error('Core 尚未就绪');
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

  private replaceRuntimeSelection(groups: ProxyGroupSnapshot[], groupName: string,
    proxy: string): ProxyGroupSnapshot[] {
    return groups.map((group: ProxyGroupSnapshot): ProxyGroupSnapshot => group.name === groupName ? {
      name: group.name,
      type: group.type,
      selected: proxy,
      selectable: group.selectable,
      hidden: group.hidden,
      nodes: group.nodes
    } : group);
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
    if (this.foreground && this.pollTimer === undefined) {
      this.pollTimer = setInterval((): void => { this.refresh(); }, this.refreshIntervalMs);
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
