import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ProxyDelayProgress, ProxyDelayProgressListener } from '../models/CoreControlProtocol';
import { Profile, ProfileStoreSnapshot } from '../models/ProfileModels';
import {
  appendTrafficSample,
  ConnectionSnapshot,
  ConnectionsSnapshot,
  DashboardSnapshot,
  DEFAULT_RUNTIME_MODE,
  GroupDelayResult,
  mergeGroupDelay,
  ProxyDelayResult,
  ProxyDelayOperationRegistry,
  ProxyGroupSnapshot,
  ProxySelection,
  ProxySnapshot,
  ProxySnapshotSource,
  preserveTestedProxyDelays,
  pruneProxySelections,
  RequestRecord,
  resolveSelectedProxyGroup,
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

interface DelayOperationContext {
  operationId: string;
  group: string;
  proxy: string;
  generation: number;
  profileSignature: string;
  profileId: string;
  configPath: string;
  runtime: boolean;
}

class RuntimeStore {
  private coreAvailable: boolean = false;
  private refreshing: boolean = false;
  private previewLoading: boolean = false;
  private dashboard: DashboardSnapshot | undefined;
  private proxies: ProxyGroupSnapshot[] = [];
  private proxySource: ProxySnapshotSource = ProxySnapshotSource.NONE;
  private proxyMode: RuntimeMode = DEFAULT_RUNTIME_MODE;
  private proxySelections: ProxySelection[] = [];
  private selectedProxyGroup: string = '';
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
  private dashboardRefreshMerger: RuntimeRequestMerger = new RuntimeRequestMerger();
  private proxyRefreshMerger: RuntimeRequestMerger = new RuntimeRequestMerger();
  private connectionRefreshMerger: RuntimeRequestMerger = new RuntimeRequestMerger();
  private refreshIntervalMs: number = 3000;
  private profileId: string = '';
  private configPath: string = '';
  private profileSignature: string = '';
  private previewGeneration: number = 0;
  private delayRegistry: ProxyDelayOperationRegistry = new ProxyDelayOperationRegistry();
  private delayContexts: Map<string, DelayOperationContext> = new Map<string, DelayOperationContext>();
  private modePreferenceGeneration: number = 0;
  private loadedModePreferenceKey: string = '';
  private foreground: boolean = true;
  private lifecycleGeneration: number = 0;
  private runtimeSnapshotGeneration: number = 0;

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
          this.runtimeSnapshotGeneration += 1;
          this.trafficHistory = [];
          this.invalidateDelayOperations();
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
        this.runtimeSnapshotGeneration += 1;
        this.invalidateDelayOperations();
        this.stopPolling();
        this.finishActiveRequests();
        this.dashboard = undefined;
        this.connections = [];
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
      proxyMode: this.proxyMode,
      proxySelections: this.proxySelections.slice(),
      selectedProxyGroup: this.selectedProxyGroup,
      delayOperations: this.delayRegistry.snapshots(),
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
    this.refreshProxySnapshot();
    this.refreshConnectionSnapshot();
    return this.dashboardRefreshMerger.run((): Promise<void> => this.refreshInternal());
  }

  async selectProxy(group: string, proxy: string): Promise<void> {
    if (this.profileId.length === 0) {
      throw new Error('请先选择活动配置');
    }
    await this.runAction(`select:${group}`, async (): Promise<void> => {
      this.requireSelectableNode(group, proxy);
      const profileId = this.profileId;
      const mode = this.proxyMode;
      if (this.coreAvailable) {
        const payload: SelectProxyCommandPayload = { group: group, proxy: proxy };
        this.requireOK<Object>(await runtimeControlService.execute<Object>('selectProxy', payload));
      } else {
        await preferenceRepository.setProxySelection(profileId, mode, group, proxy);
      }
      if (profileId !== this.profileId || mode !== this.proxyMode) {
        return;
      }
      this.proxies = this.replaceRuntimeSelection(this.proxies, group, proxy);
      this.proxySelections = this.replaceSelection(this.proxySelections, group, proxy);
      this.publish();
    });
  }

  async selectProxyGroup(group: string): Promise<void> {
    if (this.profileId.length === 0) {
      throw new Error('请先选择活动配置');
    }
    const resolved = resolveSelectedProxyGroup(this.proxies, this.proxyMode, group);
    if (resolved !== group) {
      throw new Error('代理分组已失效');
    }
    const previous = this.selectedProxyGroup;
    const profileId = this.profileId;
    const mode = this.proxyMode;
    this.selectedProxyGroup = group;
    this.publish();
    try {
      await preferenceRepository.setProxyGroup(profileId, mode, group);
    } catch (error) {
      if (profileId === this.profileId && mode === this.proxyMode && this.selectedProxyGroup === group) {
        this.selectedProxyGroup = previous;
        this.publish();
      }
      throw new Error('代理分组保存失败');
    }
  }

  async testDelay(group: string, proxy: string, testUrl: string): Promise<number> {
    this.requireProxyNode(group, proxy);
    if (this.delayRegistry.hasDirectOperation(group, proxy)) {
      throw new Error('该节点正在测速');
    }
    const context = this.beginDelayOperation(group, proxy, [proxy]);
    let delay = -1;
    hilog.info(DELAY_LOG_DOMAIN, DELAY_LOG_TAG,
      'start operation=%{public}s mode=%{public}s generation=%{public}d',
      context.operationId.substring(0, 8), context.runtime ? 'runtime' : 'preview', context.generation);
    const progressListener: ProxyDelayProgressListener = (progress: ProxyDelayProgress): void => {
      this.applyDelayProgress(progress);
    };
    try {
      const result = await this.executeGroupDelay(group, proxy, testUrl, context.operationId, 1, context.runtime,
        progressListener);
      if (!this.isDelayContextCurrent(context)) {
        return delay;
      }
      const nodeResult = result.results.find((item): boolean => item.proxy === proxy);
      this.applyDelayResults(context, result.results);
      delay = nodeResult?.delay ?? -1;
    } catch (error) {
      if (!this.isDelayContextCurrent(context)) {
        return delay;
      }
      throw new Error(this.errorMessage(error));
    } finally {
      this.finishDelayOperation(context);
    }
    return delay;
  }

  async testGroupDelay(group: string, testUrl: string): Promise<void> {
    if (this.delayRegistry.hasGroupOperation(group)) {
      throw new Error('该分组正在执行全部测速');
    }
    const targetGroup = this.proxies.find((item: ProxyGroupSnapshot): boolean => item.name === group);
    if (targetGroup === undefined || targetGroup.nodes.length === 0) {
      throw new Error('当前代理组没有可测试节点');
    }
    const targets = targetGroup.nodes.map((node): string => node.name);
    const context = this.beginDelayOperation(group, '', targets);
    const progressListener: ProxyDelayProgressListener = (progress: ProxyDelayProgress): void => {
      this.applyDelayProgress(progress);
    };
    try {
      const result = await this.executeGroupDelay(group, '', testUrl, context.operationId,
        targetGroup.nodes.length, context.runtime, progressListener);
      if (this.isDelayContextCurrent(context)) {
        this.applyDelayResults(context, result.results);
      }
    } catch (error) {
      if (!this.isDelayContextCurrent(context)) {
        return;
      }
      throw new Error(this.errorMessage(error));
    } finally {
      this.finishDelayOperation(context);
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
      const generation = ++this.runtimeSnapshotGeneration;
      const payload: SetModeCommandPayload = { mode: mode };
      this.requireOK<Object>(await runtimeControlService.execute<Object>('setRuntimeMode', payload));
      await this.refreshDashboard(generation);
      await this.refreshProxies(generation);
      this.publish();
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
    this.invalidateDelayOperations();
    this.profileSignature = signature;
    this.profileId = active?.id ?? '';
    this.configPath = active?.localPath ?? '';
    this.previewGeneration += 1;
    this.runtimeSnapshotGeneration += 1;
    this.modePreferenceGeneration += 1;
    this.loadedModePreferenceKey = '';
    this.proxyMode = DEFAULT_RUNTIME_MODE;
    this.proxySelections = [];
    this.selectedProxyGroup = '';
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
      this.selectedProxyGroup = '';
      this.previewLoading = false;
      this.publish();
      return;
    }
    try {
      if (!this.coreAvailable) {
        await this.loadPreview(generation);
      } else {
        await this.refresh();
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
      await this.ensureModePreferences(snapshot.mode);
      await this.reconcileProxyPreferences();
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

  private async ensureModePreferences(mode: RuntimeMode): Promise<void> {
    this.proxyMode = mode;
    if (this.profileId.length === 0) {
      this.proxySelections = [];
      this.selectedProxyGroup = '';
      this.loadedModePreferenceKey = '';
      return;
    }
    const key = `${this.profileId.length}:${this.profileId}:${mode}`;
    if (key === this.loadedModePreferenceKey) {
      return;
    }
    const generation = ++this.modePreferenceGeneration;
    const profileId = this.profileId;
    const selections = await preferenceRepository.getProxySelections(profileId, mode);
    const selectedGroup = await preferenceRepository.getProxyGroup(profileId, mode);
    if (generation !== this.modePreferenceGeneration || profileId !== this.profileId || mode !== this.proxyMode) {
      return;
    }
    this.proxySelections = selections;
    this.selectedProxyGroup = selectedGroup;
    this.loadedModePreferenceKey = key;
  }

  private async reconcileProxyPreferences(): Promise<void> {
    if (this.profileId.length === 0 || this.proxies.length === 0) {
      return;
    }
    const profileId = this.profileId;
    const mode = this.proxyMode;
    const validSelections = pruneProxySelections(this.proxies, this.proxySelections);
    if (validSelections.length !== this.proxySelections.length) {
      this.proxySelections = validSelections;
      await preferenceRepository.replaceProxySelections(profileId, mode, validSelections);
    }
    const resolvedGroup = resolveSelectedProxyGroup(this.proxies, mode, this.selectedProxyGroup);
    if (resolvedGroup !== this.selectedProxyGroup) {
      this.selectedProxyGroup = resolvedGroup;
      if (resolvedGroup.length > 0) {
        await preferenceRepository.setProxyGroup(profileId, mode, resolvedGroup);
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
    const runtimeSnapshotGeneration = this.runtimeSnapshotGeneration;
    this.refreshing = true;
    this.publish();
    try {
      if (!await this.refreshDashboard(runtimeSnapshotGeneration)) {
        return;
      }
      this.publish();
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

  private async refreshDashboard(expectedGeneration: number = this.runtimeSnapshotGeneration): Promise<boolean> {
    const response = await runtimeControlService.execute<DashboardSnapshot>('dashboardSnapshot');
    const dashboard = this.requireSuccess<DashboardSnapshot>(response);
    if (expectedGeneration !== this.runtimeSnapshotGeneration) {
      return false;
    }
    this.dashboard = dashboard;
    this.trafficHistory = appendTrafficSample(this.trafficHistory, {
      timestamp: Date.now(),
      uploadSpeed: this.dashboard.uploadSpeed,
      downloadSpeed: this.dashboard.downloadSpeed
    });
    return true;
  }

  private refreshProxySnapshot(): void {
    const lifecycleGeneration = this.lifecycleGeneration;
    const runtimeSnapshotGeneration = this.runtimeSnapshotGeneration;
    this.proxyRefreshMerger.run(async (): Promise<void> => {
      try {
        if (await this.refreshProxies(runtimeSnapshotGeneration)) {
          this.publish();
        }
      } catch (error) {
        if (this.foreground && lifecycleGeneration === this.lifecycleGeneration) {
          this.reportBackgroundError(this.errorMessage(error));
        }
      }
    });
  }

  private refreshConnectionSnapshot(): void {
    const lifecycleGeneration = this.lifecycleGeneration;
    this.connectionRefreshMerger.run(async (): Promise<void> => {
      try {
        await this.refreshConnections();
        if (lifecycleGeneration === this.lifecycleGeneration) {
          this.publish();
        }
      } catch (error) {
        if (this.foreground && lifecycleGeneration === this.lifecycleGeneration) {
          this.reportBackgroundError(this.errorMessage(error));
        }
      }
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

  private async refreshProxies(expectedGeneration: number = this.runtimeSnapshotGeneration): Promise<boolean> {
    const response = await runtimeControlService.execute<ProxySnapshot>('proxySnapshot');
    const snapshot = this.requireSuccess<ProxySnapshot>(response);
    if (expectedGeneration !== this.runtimeSnapshotGeneration) {
      return false;
    }
    this.proxies = preserveTestedProxyDelays(snapshot.groups, this.proxies);
    this.proxySource = ProxySnapshotSource.RUNTIME;
    await this.ensureModePreferences(snapshot.mode);
    if (expectedGeneration !== this.runtimeSnapshotGeneration) {
      return false;
    }
    await this.reconcileProxyPreferences();
    return expectedGeneration === this.runtimeSnapshotGeneration;
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
    const context = this.delayContexts.get(progress.operationId);
    if (context === undefined || context.group !== progress.group || !this.isDelayContextCurrent(context) ||
      !this.delayRegistry.accept(progress.operationId, progress.group, progress.proxy)) {
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

  private beginDelayOperation(group: string, proxy: string, targets: string[]): DelayOperationContext {
    const context: DelayOperationContext = {
      operationId: util.generateRandomUUID(),
      group: group,
      proxy: proxy,
      generation: this.previewGeneration,
      profileSignature: this.profileSignature,
      profileId: this.profileId,
      configPath: this.configPath,
      runtime: this.coreAvailable && this.proxySource === ProxySnapshotSource.RUNTIME
    };
    this.delayContexts.set(context.operationId, context);
    this.delayRegistry.start(context.operationId, group, proxy, targets);
    this.publish();
    return context;
  }

  private applyDelayResults(context: DelayOperationContext, results: ProxyDelayResult[]): void {
    const accepted = results.filter((result): boolean =>
      this.delayRegistry.accept(context.operationId, context.group, result.proxy));
    if (accepted.length > 0) {
      this.proxies = mergeGroupDelay(this.proxies, context.group, accepted);
      this.publish();
    }
  }

  private finishDelayOperation(context: DelayOperationContext): void {
    const current = this.isDelayContextCurrent(context);
    const pending = this.delayRegistry.complete(context.operationId);
    this.delayContexts.delete(context.operationId);
    if (current && pending.length > 0) {
      this.proxies = mergeGroupDelay(this.proxies, context.group,
        pending.map((proxy: string): ProxyDelayResult => ({
          proxy: proxy,
          delay: -1,
          alive: false
        })));
    }
    this.publish();
  }

  private isDelayContextCurrent(context: DelayOperationContext): boolean {
    if (this.delayContexts.get(context.operationId) !== context ||
      this.previewGeneration !== context.generation || this.profileSignature !== context.profileSignature ||
      this.profileId !== context.profileId || this.configPath !== context.configPath) {
      return false;
    }
    return context.runtime ? this.coreAvailable : !this.coreAvailable;
  }

  private invalidateDelayOperations(): void {
    this.delayRegistry.invalidate();
    this.delayContexts.clear();
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

  private requireProxyNode(groupName: string, proxy: string): void {
    const group = this.proxies.find((item: ProxyGroupSnapshot): boolean => item.name === groupName);
    if (group === undefined || !group.nodes.some((node): boolean => node.name === proxy)) {
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
      this.pollTimer = setTimeout((): void => {
        this.pollTimer = undefined;
        if (!this.foreground || !this.coreAvailable) {
          return;
        }
        this.refresh();
        this.startPolling();
      }, this.refreshIntervalMs);
    }
  }

  private stopPolling(): void {
    if (this.pollTimer !== undefined) {
      clearTimeout(this.pollTimer);
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
