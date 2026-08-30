import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { CoreEvent, CoreEventType, CoreResult, CoreRuntimeState } from '../models/CoreModels';
import {
  DEFAULT_RUNTIME_MODE,
  ProxyGroupSnapshot,
  ProxySelection,
  ProxySnapshot,
  RuntimeCommandResponse,
  RuntimeMode
} from '../models/RuntimeModels';
import {
  CoreServiceState,
  ProxyState,
  RuntimeLifecycleSnapshot
} from '../models/VpnModels';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { coreClient } from '../services/CoreClient';
import { coreControlServer } from '../services/CoreControlServer';
import { CoreRecoveryDecision, CoreRecoveryPolicy } from '../services/CoreRecoveryPolicy';
import { ProtectChannelServer, SocketProtector } from '../services/ProtectChannelServer';
import { publishVpnState } from '../services/VpnStatePublisher';
import { vpnNotificationService } from '../services/VpnNotificationService';

const DOMAIN = 0x4E4C;
const TAG = 'NlashProxyVpn';
const DEFAULT_MTU = 1400;

interface LifecycleCommand {
  type: string;
  payload?: Object;
}

interface ReloadCorePayload {
  profileId: string;
  configPath: string;
  profileSignature: string;
}

interface SetProxyEnabledPayload {
  enabled: boolean;
}

interface SetRuntimeModePayload {
  mode: RuntimeMode;
}

interface SelectProxyPayload {
  group: string;
  proxy: string;
}

class VpnSocketProtector implements SocketProtector {
  private readonly connection: vpnExtension.VpnConnection;

  constructor(connection: vpnExtension.VpnConnection) {
    this.connection = connection;
  }

  async protect(socketFd: number): Promise<void> {
    try {
      await this.connection.protect(socketFd);
    } catch (error) {
      const businessError = error as BusinessError;
      throw new Error(`VpnConnection.protect failed code=${businessError.code ?? 'unknown'}`);
    }
  }
}

export default class ProxyVpnAbility extends VpnExtensionAbility {
  private vpnConnection: vpnExtension.VpnConnection | undefined;
  private protectChannel: ProtectChannelServer | undefined;
  private tunFd: number = -1;
  private destroying: boolean = false;
  private unsubscribeCore: (() => void) | undefined;
  private lifecycleQueue: Promise<void> = Promise.resolve();
  private recoveryPolicy: CoreRecoveryPolicy = new CoreRecoveryPolicy();
  private recoveryOperation: Promise<void> | undefined;
  private coreState: CoreServiceState = CoreServiceState.STOPPED;
  private proxyState: ProxyState = ProxyState.DISABLED;
  private runtimeConfigPath: string = '';
  private runtimeProfileId: string = '';
  private runtimeProfileSignature: string = '';
  private runtimeSelections: ProxySelection[] = [];
  private runtimeDefaultSelections: ProxySelection[] = [];
  private runtimeMode: RuntimeMode = DEFAULT_RUNTIME_MODE;
  private runtimeMtu: number = DEFAULT_MTU;
  private desiredProxyEnabled: boolean = false;
  private lastLifecycleMessage: string = '';

  onCreate(want: Want): void {
    this.destroying = false;
    this.runtimeProfileId = this.stringParameter(want, 'profileId');
    this.runtimeConfigPath = this.stringParameter(want, 'configPath');
    this.runtimeProfileSignature = this.stringParameter(want, 'profileSignature');
    vpnNotificationService.start(this.context.getApplicationContext(), (): Promise<void> =>
      this.enqueue((): Promise<void> => this.disableProxy(false))).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'notification service initialization failed');
    });
    coreControlServer.start((command: string): Promise<string | undefined> =>
      this.handleControlCommand(command)).catch((): void => {
      this.setFailure('Core 控制通道初始化失败');
    });
    this.recoveryPolicy.reset();
    this.unsubscribeCore = coreClient.subscribe((event: CoreEvent): void => {
      if (event.type === CoreEventType.PROTECT_FAILURE) {
        this.handleProtectFailure();
      } else if (event.type === CoreEventType.UNEXPECTED_EXIT) {
        this.beginRecovery();
      }
    });
    hilog.info(DOMAIN, TAG, 'onCreate profile=%{public}s', this.runtimeProfileId);
    if (this.runtimeConfigPath.length === 0) {
      this.coreState = CoreServiceState.WAITING_CONFIG;
      this.publish('等待活动配置');
      return;
    }
    this.enqueue((): Promise<void> => this.loadCore(
      this.runtimeProfileId, this.runtimeConfigPath, this.runtimeProfileSignature, false)).catch((): void => {});
  }

  onDestroy(): void {
    this.destroying = true;
    vpnNotificationService.stop().catch((): void => {
      hilog.warn(DOMAIN, TAG, 'notification service shutdown failed');
    });
    coreControlServer.stop();
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.enqueue((): Promise<void> => this.shutdown()).catch((error: Error): void => {
      hilog.error(DOMAIN, TAG, 'shutdown failed: %{public}s', this.errorMessage(error));
    });
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.lifecycleQueue.then(operation, operation);
    this.lifecycleQueue = next.then((): void => {}, (): void => {});
    return next;
  }

  private async handleControlCommand(raw: string): Promise<string | undefined> {
    let command: LifecycleCommand;
    try {
      command = JSON.parse(raw) as LifecycleCommand;
    } catch (error) {
      return undefined;
    }
    if (command.type === 'lifecycleSnapshot') {
      return this.successResponse();
    }
    if (command.type === 'setProxyEnabled') {
      const payload = command.payload as SetProxyEnabledPayload | undefined;
      if (payload === undefined || typeof payload.enabled !== 'boolean') {
        return this.failureResponse('INVALID_ARGUMENT', '代理开关参数无效');
      }
      try {
        await this.enqueue((): Promise<void> => payload.enabled ? this.enableProxy() : this.disableProxy(false));
        return this.successResponse();
      } catch (error) {
        return this.failureResponse('PROXY_TRANSITION_FAILED', this.errorMessage(error));
      }
    }
    if (command.type === 'reloadCore') {
      const payload = command.payload as ReloadCorePayload | undefined;
      if (payload === undefined || typeof payload.profileId !== 'string' ||
        typeof payload.configPath !== 'string' || typeof payload.profileSignature !== 'string') {
        return this.failureResponse('INVALID_ARGUMENT', 'Core 重载参数无效');
      }
      try {
        await this.enqueue((): Promise<void> => this.loadCore(
          payload.profileId, payload.configPath, payload.profileSignature, true));
        return this.successResponse();
      } catch (error) {
        return this.failureResponse('RELOAD_FAILED', this.errorMessage(error));
      }
    }
    if (command.type === 'restartCore') {
      try {
        await this.enqueue((): Promise<void> => this.loadCore(
          this.runtimeProfileId, this.runtimeConfigPath, this.runtimeProfileSignature, true));
        return this.successResponse();
      } catch (error) {
        return this.failureResponse('RESTART_FAILED', this.errorMessage(error));
      }
    }
    if (command.type === 'selectProxy') {
      const payload = command.payload as SelectProxyPayload | undefined;
      if (payload === undefined || typeof payload.group !== 'string' || typeof payload.proxy !== 'string' ||
        payload.group.length === 0 || payload.proxy.length === 0) {
        return this.failureResponse('INVALID_ARGUMENT', '节点选择参数无效');
      }
      let response = '';
      try {
        await this.enqueue(async (): Promise<void> => {
          response = await this.selectRuntimeProxy(raw, payload);
        });
        return response;
      } catch (error) {
        return this.failureResponse('SELECT_FAILED', this.errorMessage(error));
      }
    }
    if (command.type === 'setRuntimeMode') {
      const payload = command.payload as SetRuntimeModePayload | undefined;
      if (payload === undefined || !this.isRuntimeMode(payload.mode)) {
        return this.failureResponse('INVALID_ARGUMENT', '代理模式参数无效');
      }
      try {
        await this.enqueue((): Promise<void> => this.setRuntimeMode(payload.mode));
        return this.successResponse();
      } catch (error) {
        return this.failureResponse('MODE_CHANGE_FAILED', this.errorMessage(error));
      }
    }
    if (command.type === 'applyProxySelections') {
      try {
        await this.enqueue((): Promise<void> => this.restoreRuntimeModeAndSelections());
        return this.successResponse();
      } catch (error) {
        return this.failureResponse('APPLY_SELECTIONS_FAILED', this.errorMessage(error));
      }
    }
    return undefined;
  }

  private async loadCore(profileId: string, configPath: string,
    profileSignature: string, reloading: boolean): Promise<void> {
    const restoreProxy = this.desiredProxyEnabled || this.proxyState === ProxyState.ENABLED ||
      this.proxyState === ProxyState.ENABLING;
    this.coreState = reloading ? CoreServiceState.RELOADING : CoreServiceState.STARTING;
    this.publish(reloading ? '正在重载 Core' : '正在启动 Core');
    try {
      await this.disableProxy(true);
      if (coreClient.getState() !== CoreRuntimeState.STOPPED) {
        await coreClient.stop();
      }
      this.runtimeProfileId = profileId;
      this.runtimeConfigPath = configPath;
      this.runtimeProfileSignature = profileSignature;
      this.runtimeSelections = [];
      this.runtimeDefaultSelections = [];
      this.runtimeMode = DEFAULT_RUNTIME_MODE;
      if (configPath.length === 0) {
        this.coreState = CoreServiceState.WAITING_CONFIG;
        this.proxyState = ProxyState.DISABLED;
        this.desiredProxyEnabled = false;
        this.publish('等待活动配置');
        return;
      }
      await preferenceRepository.initialize(this.context.getApplicationContext());
      this.runtimeMtu = (await preferenceRepository.getAppSettings()).mtu;
      if (!this.fileExists(configPath)) {
        throw new Error('活动配置文件不存在，请重新添加或选择配置');
      }
      const validation = await coreClient.validateConfig(configPath);
      if (!validation.ok) {
        throw new Error(`Configuration validation failed: ${validation.code}`);
      }
      const workDir = `${this.context.filesDir}/core/work`;
      await this.ensureDirectory(workDir);
      const result = await coreClient.start({ configPath: configPath, workDir: workDir });
      if (!result.ok || coreClient.getState() !== CoreRuntimeState.RUNNING) {
        throw new Error(`Core start failed: ${result.code}: ${result.message}`);
      }
      await this.captureRuntimeDefaults();
      await this.restoreRuntimeModeAndSelections();
      this.coreState = CoreServiceState.RUNNING;
      this.proxyState = ProxyState.DISABLED;
      this.publish('Core 已运行，代理未开启');
      this.recoveryPolicy.reset();
      if (restoreProxy && !this.destroying) {
        this.desiredProxyEnabled = true;
        await this.enableProxy();
      }
    } catch (error) {
      const message = this.errorMessage(error);
      const nativeRunning = coreClient.getState() === CoreRuntimeState.RUNNING;
      const nativeProxyEnabled = nativeRunning && coreClient.isProxyEnabled();
      if (!nativeProxyEnabled) {
        await this.cleanupProxyResources();
      }
      if (nativeProxyEnabled) {
        this.desiredProxyEnabled = true;
        this.coreState = CoreServiceState.ERROR;
        this.proxyState = ProxyState.ENABLED;
        this.publish(`Core 重载失败，原代理仍在运行：${message}`);
      } else if (nativeRunning) {
        this.desiredProxyEnabled = false;
        this.coreState = CoreServiceState.RUNNING;
        this.proxyState = ProxyState.ERROR;
        this.publish(`Core 已运行，代理恢复失败：${message}`);
      } else {
        this.desiredProxyEnabled = false;
        this.coreState = CoreServiceState.ERROR;
        this.proxyState = ProxyState.DISABLED;
        this.publish(message);
      }
      throw new Error(message);
    }
  }

  private async enableProxy(): Promise<void> {
    this.desiredProxyEnabled = true;
    if (this.proxyState === ProxyState.ENABLED && coreClient.isProxyEnabled()) {
      return;
    }
    if (this.coreState !== CoreServiceState.RUNNING || coreClient.getState() !== CoreRuntimeState.RUNNING) {
      this.desiredProxyEnabled = false;
      throw new Error('Core 尚未就绪');
    }
    this.proxyState = ProxyState.ENABLING;
    this.publish('正在创建 VPN/TUN');
    const connection = vpnExtension.createVpnConnection(this.context);
    this.vpnConnection = connection;
    try {
      const fd = await connection.create(this.vpnConfig());
      if (fd < 0) {
        throw new Error(`VpnConnection.create returned invalid fd=${fd}`);
      }
      this.tunFd = fd;
      const generation = util.generateRandomUUID();
      const protectSocketPath = `${this.context.filesDir}/p-${generation.substring(0, 8)}.sock`;
      const channel = new ProtectChannelServer(
        protectSocketPath,
        generation,
        new VpnSocketProtector(connection),
        (message: string): void => {
          hilog.warn(DOMAIN, TAG, 'protect channel diagnostic: %{public}s', message);
        }
      );
      await channel.start();
      this.protectChannel = channel;
      const result: CoreResult = await coreClient.enableProxy({
        tunFd: fd,
        mtu: this.runtimeMtu,
        protectSocketPath: protectSocketPath,
        generation: generation
      });
      if (!result.ok || !coreClient.isProxyEnabled()) {
        throw new Error(`Core proxy enable failed: ${result.code}: ${result.message}`);
      }
      await this.restoreRuntimeModeAndSelections();
      this.proxyState = ProxyState.ENABLED;
      this.publish('代理已开启');
    } catch (error) {
      if (coreClient.getState() === CoreRuntimeState.RUNNING && coreClient.isProxyEnabled()) {
        try {
          await coreClient.disableProxy();
        } catch (disableError) {
          hilog.error(DOMAIN, TAG, 'proxy rollback failed');
        }
      }
      await this.cleanupProxyResources();
      this.desiredProxyEnabled = false;
      this.proxyState = ProxyState.ERROR;
      const message = this.errorMessage(error);
      this.publish(message);
      throw new Error(message);
    }
  }

  private async disableProxy(preserveDesired: boolean): Promise<void> {
    if (!preserveDesired) {
      this.desiredProxyEnabled = false;
    }
    const hasProxyResources = this.vpnConnection !== undefined || this.protectChannel !== undefined ||
      this.tunFd >= 0 || coreClient.isProxyEnabled();
    if (!hasProxyResources) {
      this.proxyState = ProxyState.DISABLED;
      return;
    }
    this.proxyState = ProxyState.DISABLING;
    this.publish('正在关闭代理');
    let coreReconfigured = false;
    try {
      if (coreClient.getState() === CoreRuntimeState.RUNNING && coreClient.isProxyEnabled()) {
        const result = await coreClient.disableProxy();
        if (!result.ok) {
          throw new Error(`Core proxy disable failed: ${result.code}: ${result.message}`);
        }
        coreReconfigured = true;
      }
    } catch (error) {
      const failure = new Error(this.errorMessage(error));
      this.desiredProxyEnabled = true;
      this.proxyState = ProxyState.ENABLED;
      this.publish(`关闭代理失败，原 VPN/TUN 已保留：${failure.message}`);
      throw failure;
    }
    let restoreFailure: Error | undefined;
    if (coreReconfigured) {
      try {
        await this.restoreRuntimeModeAndSelections();
      } catch (error) {
        restoreFailure = new Error(this.errorMessage(error));
      }
    }
    await this.cleanupProxyResources();
    if (restoreFailure !== undefined) {
      this.proxyState = ProxyState.ERROR;
      this.publish(`代理已关闭，但节点选择恢复失败：${restoreFailure.message}`);
      throw restoreFailure;
    }
    this.proxyState = ProxyState.DISABLED;
    this.publish('代理已关闭，Core 继续运行');
  }

  private async cleanupProxyResources(): Promise<void> {
    this.tunFd = -1;
    const channel = this.protectChannel;
    this.protectChannel = undefined;
    if (channel !== undefined) {
      try {
        await channel.stop();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'protect channel cleanup failed');
      }
    }
    const connection = this.vpnConnection;
    this.vpnConnection = undefined;
    if (connection !== undefined) {
      try {
        await connection.destroy();
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'VPN connection cleanup failed');
      }
    }
  }

  private handleProtectFailure(): void {
    if (this.destroying) {
      return;
    }
    this.enqueue(async (): Promise<void> => {
      try {
        await this.disableProxy(false);
        this.proxyState = ProxyState.ERROR;
        this.publish('Outbound socket protect failed');
      } catch (error) {
        this.publish(`Outbound socket protect failed; ${this.errorMessage(error)}`);
      }
    }).catch((): void => {});
  }

  private beginRecovery(): void {
    if (this.destroying || this.recoveryOperation !== undefined) {
      return;
    }
    const decision = this.recoveryPolicy.onUnexpectedExit();
    if (decision === CoreRecoveryDecision.IGNORE) {
      return;
    }
    if (decision === CoreRecoveryDecision.STOP) {
      this.enqueue(async (): Promise<void> => {
        this.desiredProxyEnabled = false;
        await this.cleanupProxyResources();
        this.coreState = CoreServiceState.ERROR;
        this.proxyState = ProxyState.DISABLED;
        this.publish('Core exited again after one recovery');
      }).catch((): void => {});
      return;
    }
    const operation = this.enqueue((): Promise<void> => this.loadCore(
      this.runtimeProfileId, this.runtimeConfigPath, this.runtimeProfileSignature, true));
    this.recoveryOperation = operation;
    operation.then((): void => {
      this.recoveryOperation = undefined;
      this.recoveryPolicy.finishRecovery();
    }, (): void => {
      this.recoveryOperation = undefined;
      this.recoveryPolicy.finishRecovery();
      if (this.proxyState !== ProxyState.ENABLED) {
        this.coreState = CoreServiceState.ERROR;
        this.proxyState = ProxyState.DISABLED;
        this.publish('Core recovery failed');
      }
    });
  }

  private async shutdown(): Promise<void> {
    this.desiredProxyEnabled = false;
    try {
      await this.disableProxy(false);
    } catch (error) {
    }
    if (coreClient.getState() !== CoreRuntimeState.STOPPED) {
      try {
        await coreClient.stop();
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'core stop failed');
      }
    }
    this.unsubscribeCore?.();
    this.unsubscribeCore = undefined;
    this.coreState = CoreServiceState.STOPPED;
    this.proxyState = ProxyState.DISABLED;
    this.publish('Core 已停止');
  }

  private async captureRuntimeDefaults(): Promise<void> {
    const snapshot = await this.runtimeProxySnapshot();
    this.runtimeMode = this.isRuntimeMode(snapshot.mode) ? snapshot.mode : DEFAULT_RUNTIME_MODE;
    this.runtimeDefaultSelections = snapshot.groups
      .filter((group: ProxyGroupSnapshot): boolean => group.selectable && group.selected.length > 0)
      .map((group: ProxyGroupSnapshot): ProxySelection => ({ group: group.name, proxy: group.selected }));
  }

  private async restoreRuntimeModeAndSelections(): Promise<void> {
    if (coreClient.getState() !== CoreRuntimeState.RUNNING) {
      return;
    }
    const modePayload: SetRuntimeModePayload = { mode: this.runtimeMode };
    await this.executeRequiredOK('setMode', modePayload);
    const snapshot = await this.runtimeProxySnapshot();
    const saved = this.runtimeProfileId.length > 0 ?
      await preferenceRepository.getProxySelections(this.runtimeProfileId, this.runtimeMode) : [];
    const validSaved = saved.filter((selection: ProxySelection): boolean => {
      const group = snapshot.groups.find((item: ProxyGroupSnapshot): boolean => item.name === selection.group);
      return group !== undefined && group.selectable &&
        group.nodes.some((node): boolean => node.name === selection.proxy);
    });
    const effective = this.runtimeDefaultSelections.slice();
    validSaved.forEach((selection: ProxySelection): void => {
      const index = effective.findIndex((item: ProxySelection): boolean => item.group === selection.group);
      if (index >= 0) {
        effective[index] = { group: selection.group, proxy: selection.proxy };
      } else {
        effective.push({ group: selection.group, proxy: selection.proxy });
      }
    });
    await this.applyRuntimeSelections(effective);
    this.runtimeSelections = effective;
    if (this.runtimeProfileId.length > 0) {
      try {
        await preferenceRepository.replaceProxySelections(this.runtimeProfileId, this.runtimeMode, validSaved);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'failed to prune proxy selections');
      }
    }
  }

  private async applyRuntimeSelections(selections: ProxySelection[]): Promise<void> {
    for (let index = 0; index < selections.length; index += 1) {
      const selection = selections[index];
      const payload: SelectProxyPayload = {
        group: selection.group,
        proxy: selection.proxy
      };
      await this.executeRequiredOK('selectProxy', payload);
    }
  }

  private async selectRuntimeProxy(raw: string, payload: SelectProxyPayload): Promise<string> {
    const snapshot = await this.runtimeProxySnapshot();
    const group = snapshot.groups.find((item: ProxyGroupSnapshot): boolean => item.name === payload.group);
    const originalProxy = group?.selected ?? '';
    const responseRaw = await coreClient.executeCommand(raw);
    const response = this.parseCommandResponse<Object>(responseRaw);
    if (!response.ok) {
      return responseRaw;
    }
    try {
      if (this.runtimeProfileId.length > 0) {
        await preferenceRepository.setProxySelection(
          this.runtimeProfileId, this.runtimeMode, payload.group, payload.proxy);
      }
      this.runtimeSelections = this.replaceSelection(this.runtimeSelections, payload.group, payload.proxy);
      return responseRaw;
    } catch (error) {
      let rollbackFailed = false;
      if (originalProxy.length > 0 && originalProxy !== payload.proxy) {
        try {
          const rollbackPayload: SelectProxyPayload = {
            group: payload.group,
            proxy: originalProxy
          };
          await this.executeRequiredOK('selectProxy', rollbackPayload);
        } catch (rollbackError) {
          rollbackFailed = true;
        }
      }
      return this.failureResponse('SELECTION_SAVE_FAILED', rollbackFailed ?
        '节点选择保存失败，且 Core 节点恢复失败' : '节点选择保存失败，已恢复原节点');
    }
  }

  private async setRuntimeMode(mode: RuntimeMode): Promise<void> {
    const previousMode = this.runtimeMode;
    const previousSelections = this.runtimeSelections.slice();
    try {
      this.runtimeMode = mode;
      await this.restoreRuntimeModeAndSelections();
    } catch (error) {
      this.runtimeMode = previousMode;
      try {
        const rollbackModePayload: SetRuntimeModePayload = { mode: previousMode };
        await this.executeRequiredOK('setMode', rollbackModePayload);
        await this.applyRuntimeSelections(previousSelections);
        this.runtimeSelections = previousSelections;
      } catch (rollbackError) {
        throw new Error('代理模式切换失败，且原模式恢复失败');
      }
      throw new Error(this.errorMessage(error));
    }
  }

  private async runtimeProxySnapshot(): Promise<ProxySnapshot> {
    return this.executeRequiredCommand<ProxySnapshot>('proxySnapshot');
  }

  private async executeRequiredCommand<T>(type: string, payload?: Object): Promise<T> {
    const command: LifecycleCommand = payload === undefined ? { type: type } : { type: type, payload: payload };
    const raw = await coreClient.executeCommand(JSON.stringify(command));
    const response = this.parseCommandResponse<T>(raw);
    if (!response.ok || response.data === undefined) {
      throw new Error(response.message.length > 0 ? response.message : response.code);
    }
    return response.data;
  }

  private async executeRequiredOK(type: string, payload?: Object): Promise<void> {
    const command: LifecycleCommand = payload === undefined ? { type: type } : { type: type, payload: payload };
    const response = this.parseCommandResponse<Object>(
      await coreClient.executeCommand(JSON.stringify(command)));
    if (!response.ok) {
      throw new Error(response.message.length > 0 ? response.message : response.code);
    }
  }

  private parseCommandResponse<T>(raw: string): RuntimeCommandResponse<T> {
    const response = JSON.parse(raw) as RuntimeCommandResponse<T>;
    if (typeof response.ok !== 'boolean' || typeof response.code !== 'string' ||
      typeof response.message !== 'string') {
      throw new Error('Core 返回了无效响应');
    }
    return response;
  }

  private replaceSelection(selections: ProxySelection[], group: string, proxy: string): ProxySelection[] {
    return selections.filter((selection: ProxySelection): boolean => selection.group !== group)
      .concat([{ group: group, proxy: proxy }]);
  }

  private isRuntimeMode(mode: RuntimeMode): boolean {
    return mode === RuntimeMode.RULE || mode === RuntimeMode.GLOBAL || mode === RuntimeMode.DIRECT;
  }

  private vpnConfig(): vpnExtension.VpnConfig {
    return {
      addresses: [{
        address: { address: '172.19.0.1', family: 1 },
        prefixLength: 30
      }],
      routes: [{
        interface: 'vpn-tun',
        destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
        gateway: { address: '0.0.0.0', family: 1 },
        hasGateway: false,
        isDefaultRoute: true
      }],
      dnsAddresses: ['1.1.1.1'],
      mtu: this.runtimeMtu,
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      isInternal: false,
      isBlocking: false
    };
  }

  private lifecycleSnapshot(): RuntimeLifecycleSnapshot {
    return {
      coreState: this.coreState,
      proxyState: this.proxyState,
      profileId: this.runtimeProfileId,
      profileSignature: this.runtimeProfileSignature,
      message: this.lastLifecycleMessage
    };
  }

  private successResponse(): string {
    const response: RuntimeCommandResponse<RuntimeLifecycleSnapshot> = {
      ok: true,
      code: 'OK',
      message: '',
      data: this.lifecycleSnapshot()
    };
    return JSON.stringify(response);
  }

  private failureResponse(code: string, message: string): string {
    const response: RuntimeCommandResponse<RuntimeLifecycleSnapshot> = {
      ok: false,
      code: code,
      message: message,
      data: this.lifecycleSnapshot()
    };
    return JSON.stringify(response);
  }

  private publish(message: string): void {
    this.lastLifecycleMessage = message;
    vpnNotificationService.updateLifecycle(this.coreState, this.proxyState);
    publishVpnState(this.context.getApplicationContext(), this.coreState, this.proxyState,
      message, this.runtimeProfileId, this.runtimeProfileSignature);
  }

  private setFailure(message: string): void {
    this.desiredProxyEnabled = false;
    this.coreState = CoreServiceState.ERROR;
    this.proxyState = ProxyState.ERROR;
    this.publish(message);
  }

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  private stringParameter(want: Want, name: string): string {
    const value = want.parameters?.[name];
    return typeof value === 'string' ? value : '';
  }

  private async ensureDirectory(path: string): Promise<void> {
    try {
      if (fileIo.accessSync(path)) {
        return;
      }
    } catch (error) {
    }
    await fileIo.mkdir(path, true);
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : 'Core 操作失败';
  }
}
