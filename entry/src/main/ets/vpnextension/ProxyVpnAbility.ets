import { Want } from '@kit.AbilityKit';
import { BusinessError, systemDateTime } from '@kit.BasicServicesKit';
import { fileIo } from '@kit.CoreFileKit';
import { connection, vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { CoreEvent, CoreEventType, CoreResult, CoreRuntimeState } from '../model/CoreModels';
import { DEFAULT_RUNTIME_MODE } from '../constants/RuntimeConstants';
import { BOOTSTRAP_CORE_CONFIG, BOOTSTRAP_PROFILE_SIGNATURE } from '../constants/VpnConstants';
import { buildPlatformVpnConfig, ProxySessionTimer } from '../utils/VpnUtils';
import {
  ProxyGroupSnapshot,
  ProxySelection,
  ProxySnapshot,
  RuntimeCommandResponse,
  RuntimeMode
} from '../model/RuntimeModels';
import { CoreServiceState, ProxyState, RuntimeLifecycleSnapshot } from '../model/VpnModels';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { coreClient } from '../services/CoreClient';
import { coreControlServer } from '../services/CoreControlServer';
import { CoreRecoveryDecision, CoreRecoveryPolicy } from '../services/CoreRecoveryPolicy';
import { ProtectChannelServer, SocketProtector } from '../services/ProtectChannelServer';
import { publishVpnState } from '../services/VpnStatePublisher';
import { GeneralSettings } from '../model/GeneralSettingsModels';

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

interface ApplyConfigPayload {
  configPath: string;
}

interface SetRuntimeModePayload {
  mode: RuntimeMode;
}

interface SelectProxyPayload {
  group: string;
  proxy: string;
}

/** 将协议层的 FD 保护请求交给创建本轮 TUN 的 VpnConnection。 */
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

/**
 * 系统 VPN 宿主，集中持有 Core、平台 TUN 和 protect 通道，UI 通过控制事件驱动它。
 * 生命周期变更进入同一队列；desiredProxyEnabled 表示重启后是否需要恢复代理。
 */
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
  private runtimeIpv6: boolean = false;
  private networkMonitor: connection.NetConnection | undefined;
  private desiredProxyEnabled: boolean = false;
  private lastLifecycleMessage: string = '';
  private sessionTimer: ProxySessionTimer = new ProxySessionTimer();

  onCreate(want: Want): void {
    this.destroying = false;
    const controlReady = coreControlServer.start((command: string): Promise<string | undefined> =>
      this.handleControlCommand(command));
    this.recoveryPolicy.reset();
    this.unsubscribeCore = coreClient.subscribe((event: CoreEvent): void => {
      if (event.type === CoreEventType.PROTECT_FAILURE) {
        this.handleProtectFailure();
      } else if (event.type === CoreEventType.UNEXPECTED_EXIT) {
        this.beginRecovery();
      }
    });
    hilog.info(DOMAIN, TAG, 'onCreate profile=%{public}s', this.runtimeProfileId);
    this.coreState = CoreServiceState.STARTING;
    this.publish('正在启动 Core');
    this.enqueue(async (): Promise<void> => {
      await controlReady;
      await this.loadCore('', await this.prepareBootstrapConfig(), BOOTSTRAP_PROFILE_SIGNATURE, false);
      try { this.monitorSystemDNS(); }
      catch (_error) { hilog.warn(DOMAIN, TAG, 'system DNS monitor unavailable'); }
    }).catch((error: Error): void => { this.setFailure(this.errorMessage(error)); });
  }

  onDestroy(): void {
    this.destroying = true;
    try { this.networkMonitor?.unregister((_error: BusinessError): void => {}); }
    catch (_error) { hilog.warn(DOMAIN, TAG, 'system DNS monitor cleanup failed'); }
    this.networkMonitor = undefined;
    coreControlServer.stop();
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.enqueue((): Promise<void> => this.shutdown()).catch((error: Error): void => {
      hilog.error(DOMAIN, TAG, 'shutdown failed: %{public}s', this.errorMessage(error));
    });
  }

  // 前项失败仍执行后项，但把本次错误返回给调用者，避免一次故障阻断整个队列。
  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.lifecycleQueue.then(operation, operation);
    this.lifecycleQueue = next.then((): void => {}, (): void => {});
    return next;
  }

  // 宿主接管涉及平台资源和持久化的命令，其余命令由 CoreControlServer 继续转给 Go。
  private async handleControlCommand(raw: string): Promise<string | undefined> {
    let command: LifecycleCommand;
    try {
      command = JSON.parse(raw) as LifecycleCommand;
    } catch (error) {
      return undefined;
    }
    if (command.type === 'lifecycleSnapshot') {
      await this.lifecycleQueue;
      return this.successResponse();
    }
    if (command.type === 'saveGeneralSettings') {
      const settings = command.payload as GeneralSettings | undefined;
      if (settings === undefined || settings === null || typeof settings.ipv6 !== 'boolean' ||
        typeof settings.appendSystemDns !== 'boolean') {
        return this.failureResponse('INVALID_ARGUMENT', '常规设置参数无效');
      }
      let response = '';
      try {
        await this.enqueue(async (): Promise<void> => {
          response = await this.saveGeneralSettings(raw, settings);
        });
        return response;
      } catch (error) {
        return this.failureResponse('SETTINGS_FAILED', this.errorMessage(error));
      }
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
        await this.enqueue((): Promise<void> => this.applyProfile(
          payload.profileId, payload.configPath, payload.profileSignature));
        return this.successResponse();
      } catch (error) {
        return this.failureResponse('RELOAD_FAILED', this.errorMessage(error));
      }
    }
    if (command.type === 'restartCore') {
      try {
        await this.enqueue(async (): Promise<void> => {
          this.recoveryPolicy.reset();
          await this.loadCore(this.runtimeProfileId, this.runtimeConfigPath || await this.prepareBootstrapConfig(),
            this.runtimeProfileSignature || BOOTSTRAP_PROFILE_SIGNATURE, true);
        });
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

  /** 完整重启路径：撤下代理、校验并启动 Core、恢复选择，再按原意图重新开启代理。 */
  private async loadCore(profileId: string, configPath: string,
    profileSignature: string, reloading: boolean): Promise<void> {
    const restoreProxy = this.desiredProxyEnabled || this.proxyState === ProxyState.ENABLED ||
      this.proxyState === ProxyState.ENABLING;
    const previousMode = this.runtimeMode;
    this.coreState = reloading ? CoreServiceState.RELOADING : CoreServiceState.STARTING;
    this.publish(reloading ? '正在重启 Core' : '正在启动 Core');
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
      await this.refreshSystemDNS(false);
      const result = await coreClient.start({ configPath: configPath, workDir: workDir });
      if (!result.ok || coreClient.getState() !== CoreRuntimeState.RUNNING) {
        throw new Error(`Core start failed: ${result.code}: ${result.message}`);
      }
      await this.captureRuntimeDefaults();
      if (reloading) {
        this.runtimeMode = previousMode;
      }
      await this.restoreRuntimeModeAndSelections();
      this.coreState = CoreServiceState.RUNNING;
      this.proxyState = ProxyState.DISABLED;
      this.publish('Core 已运行，代理未开启');
      if (restoreProxy && profileId.length > 0 && !this.destroying) {
        this.desiredProxyEnabled = true;
        await this.enableProxy();
      }
    } catch (error) {
      const message = this.errorMessage(error);
      const nativeRunning = coreClient.getState() === CoreRuntimeState.RUNNING;
      const nativeProxyEnabled = nativeRunning && coreClient.isProxyEnabled();
      if (!nativeProxyEnabled) {
        await this.cleanupProxyResources();
        this.finishSession();
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

  /** 热应用配置；Core 成功后若模式或选择恢复失败，回滚原配置及宿主快照。 */
  private async applyProfile(profileId: string, configPath: string, profileSignature: string): Promise<void> {
    if (this.coreState !== CoreServiceState.RUNNING || coreClient.getState() !== CoreRuntimeState.RUNNING) {
      throw new Error('Core 尚未就绪，请点击 Core 状态重试');
    }
    if (profileSignature === this.runtimeProfileSignature) {
      return;
    }
    const path = profileId.length === 0 ? await this.prepareBootstrapConfig() : configPath;
    const previousId = this.runtimeProfileId;
    const previousPath = this.runtimeConfigPath;
    const previousSignature = this.runtimeProfileSignature;
    const previousMode = this.runtimeMode;
    const previousDefaults = this.runtimeDefaultSelections.slice();
    const previousSelections = this.runtimeSelections.slice();
    let applied = false;
    this.publish('正在应用配置');
    try {
      const payload: ApplyConfigPayload = { configPath: path };
      const snapshot = await this.executeRequiredCommand<ProxySnapshot>('applyConfig', payload);
      applied = true;
      this.runtimeProfileId = profileId;
      this.runtimeConfigPath = path;
      this.runtimeProfileSignature = profileSignature;
      await this.captureRuntimeDefaults(snapshot);
      if (profileId === previousId) {
        this.runtimeMode = previousMode;
      }
      await this.restoreRuntimeModeAndSelections();
      if (profileId.length === 0) {
        await this.disableProxy(false);
      }
      this.publish(profileId.length === 0 ? 'Core 已运行，请添加有效配置' : '配置已应用，Core 继续运行');
    } catch (error) {
      this.runtimeProfileId = previousId;
      this.runtimeConfigPath = previousPath;
      this.runtimeProfileSignature = previousSignature;
      this.runtimeMode = previousMode;
      this.runtimeDefaultSelections = previousDefaults;
      this.runtimeSelections = previousSelections;
      try {
        if (applied) {
          await this.executeRequiredOK('rollbackConfig');
          const modePayload: SetRuntimeModePayload = { mode: previousMode };
          await this.executeRequiredOK('setMode', modePayload);
          await this.applyRuntimeSelections(previousSelections);
        }
      } catch (rollbackError) {
        this.coreState = CoreServiceState.ERROR;
        this.publish('配置应用失败，原配置恢复失败，正在尝试恢复 Core');
        this.beginRecovery();
        throw new Error('配置应用失败，原配置恢复失败');
      }
      if (coreClient.getState() !== CoreRuntimeState.RUNNING) {
        this.coreState = CoreServiceState.ERROR;
      }
      const message = `配置应用失败，已保留原配置：${this.errorMessage(error)}`;
      this.publish(message);
      throw new Error(message);
    }
  }

  private async saveGeneralSettings(raw: string, next: GeneralSettings): Promise<string> {
    const previous = await this.executeRequiredCommand<GeneralSettings>('generalSettings');
    const reconnect = previous.ipv6 !== next.ipv6 && this.proxyState === ProxyState.ENABLED;
    if (next.appendSystemDns) { await this.refreshSystemDNS(true); }
    if (reconnect) { await this.disableProxy(true); }
    let applied = false;
    try {
      const response = await coreClient.executeCommand(raw);
      const result = this.parseCommandResponse<GeneralSettings>(response);
      if (!result.ok) { throw new Error(result.message || '常规设置应用失败'); }
      applied = true;
      if (reconnect) { await this.enableProxy(); }
      return response;
    } catch (error) {
      try {
        if (applied) { await this.executeRequiredOK('saveGeneralSettings', previous); }
        if (reconnect) { await this.enableProxy(); }
      } catch (restoreError) {
        throw new Error('设置应用失败，原代理恢复失败，请重启 Core');
      }
      throw new Error(this.errorMessage(error));
    }
  }

  private monitorSystemDNS(): void {
    const monitor = connection.createNetConnection({ netCapabilities: {
      bearerTypes: [], networkCap: [connection.NetCap.NET_CAPABILITY_INTERNET, connection.NetCap.NET_CAPABILITY_NOT_VPN]
    } });
    this.networkMonitor = monitor;
    const refresh = (): void => {
      if (this.destroying) { return; }
      this.enqueue((): Promise<void> => this.refreshSystemDNS(false)).catch((): void => {
        hilog.warn(DOMAIN, TAG, 'system DNS refresh failed');
      });
    };
    monitor.on('netAvailable', refresh);
    monitor.on('netConnectionPropertiesChange', refresh);
    monitor.on('netLost', refresh);
    monitor.register((error: BusinessError): void => {
      if (error) { hilog.warn(DOMAIN, TAG, 'system DNS monitor unavailable'); }
    });
  }

  private async refreshSystemDNS(required: boolean): Promise<void> {
    try {
      // getDefaultNet 返回默认非 VPN 网络，不能把 TUN 的 DNS 再追加到自身上游。
      const network = await connection.getDefaultNet();
      const servers: string[] = [];
      if (network.netId !== 0) {
        const properties = await connection.getConnectionProperties(network);
        properties.dnses.forEach((address: connection.NetAddress): void => {
          const value = address.address;
          if (value.length > 0 && value !== '0.0.0.0' && value !== '::' && value !== '::1' &&
            !value.startsWith('127.') && !servers.includes(value)) { servers.push(value); }
        });
      }
      if (required && servers.length === 0) { throw new Error('当前网络未提供可用的系统 DNS'); }
      await this.executeRequiredOK('updateSystemDNS', servers.slice(0, 16));
    } catch (error) {
      if (required) { throw new Error('无法读取或应用系统 DNS，请检查当前网络后重试'); }
      hilog.warn(DOMAIN, TAG, 'system DNS refresh unavailable');
    }
  }

  /** 依次创建平台 TUN、监听 protect 通道、接入 Core，失败时回收本轮平台资源。 */
  private async enableProxy(): Promise<void> {
    if (this.proxyState === ProxyState.ENABLED && coreClient.isProxyEnabled()) {
      return;
    }
    if (this.coreState !== CoreServiceState.RUNNING || coreClient.getState() !== CoreRuntimeState.RUNNING) {
      this.desiredProxyEnabled = false;
      throw new Error('Core 尚未就绪');
    }
    if (this.runtimeProfileId.length === 0) {
      throw new Error('请先添加并选择有效配置');
    }
    this.desiredProxyEnabled = true;
    this.proxyState = ProxyState.ENABLING;
    this.publish('正在创建 VPN/TUN');
    try {
      this.runtimeMtu = (await preferenceRepository.getAppSettings(this.context.getApplicationContext())).mtu;
      this.runtimeIpv6 = (await this.executeRequiredCommand<GeneralSettings>('generalSettings')).ipv6;
      const connection = vpnExtension.createVpnConnection(this.context);
      this.vpnConnection = connection;
      const fd = await connection.create(buildPlatformVpnConfig(this.runtimeMtu, this.runtimeIpv6));
      if (fd < 0) {
        throw new Error(`VpnConnection.create returned invalid fd=${fd}`);
      }
      this.tunFd = fd;
      // 每次开启使用独立会话，旧 Core 连接不能复用新一轮的 FD 保护通道。
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
      this.sessionTimer.connected(systemDateTime.getUptime(systemDateTime.TimeType.STARTUP));
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
      this.finishSession();
      const message = this.errorMessage(error);
      this.publish(message);
      throw new Error(message);
    }
  }

  /** preserveDesired 用于重启时临时撤下代理，保留用户开启意图和会话计时。 */
  private async disableProxy(preserveDesired: boolean): Promise<void> {
    if (!preserveDesired) {
      this.desiredProxyEnabled = false;
    }
    const hasProxyResources = this.vpnConnection !== undefined || this.protectChannel !== undefined ||
      this.tunFd >= 0 || coreClient.isProxyEnabled();
    if (!hasProxyResources) {
      this.proxyState = ProxyState.DISABLED;
      if (!preserveDesired) {
        this.finishSession();
        this.publish('代理已关闭，Core 继续运行');
      }
      return;
    }
    this.proxyState = ProxyState.DISABLING;
    this.publish('正在关闭代理');
    // 必须先确认 Core 已撤下 TUN，再销毁平台连接；失败时保留仍工作的资源。
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
    if (!preserveDesired) {
      this.finishSession();
    }
    if (restoreFailure !== undefined) {
      this.proxyState = ProxyState.ERROR;
      this.publish(`代理已关闭，但节点选择恢复失败：${restoreFailure.message}`);
      throw restoreFailure;
    }
    this.proxyState = ProxyState.DISABLED;
    this.publish('代理已关闭，Core 继续运行');
  }

  // 平台原始 FD 随 VpnConnection.destroy 释放，不能与 Go 持有的副本重复关闭。
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

  // protect 失败时撤下代理并报告错误，防止出站连接反复进入自身的 VPN。
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

  // 合并重复异常事件，并遵循一次自动恢复上限，防止持续重启占用系统资源。
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
        this.finishSession();
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
        this.finishSession();
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
    this.finishSession();
    this.publish('Core 已停止');
  }

  private async captureRuntimeDefaults(current?: ProxySnapshot): Promise<void> {
    const snapshot = current ?? await this.runtimeProxySnapshot();
    this.runtimeMode = this.isRuntimeMode(snapshot.mode) ? snapshot.mode : DEFAULT_RUNTIME_MODE;
    this.runtimeDefaultSelections = snapshot.groups
      .filter((group: ProxyGroupSnapshot): boolean => group.selectable && group.selected.length > 0)
      .map((group: ProxyGroupSnapshot): ProxySelection => ({ group: group.name, proxy: group.selected }));
  }

  /** 以配置默认值为基础覆盖仍有效的保存选择，并清理已被订阅移除的节点记录。 */
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

  // 节点切换与保存作为一个用户操作处理；保存失败时尽量恢复 Core 原节点。
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

  private lifecycleSnapshot(): RuntimeLifecycleSnapshot {
    const session = this.sessionTimer.getSnapshot();
    return {
      coreState: this.coreState,
      proxyState: this.proxyState,
      profileId: this.runtimeProfileId,
      profileSignature: this.runtimeProfileSignature,
      message: this.lastLifecycleMessage,
      sessionStartedAt: session.sessionStartedAt,
      sessionEndedAt: session.sessionEndedAt
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
    const session = this.sessionTimer.getSnapshot();
    publishVpnState(this.context.getApplicationContext(), this.coreState, this.proxyState,
      message, this.runtimeProfileId, this.runtimeProfileSignature, session.sessionStartedAt, session.sessionEndedAt);
  }

  private setFailure(message: string): void {
    this.desiredProxyEnabled = false;
    this.coreState = CoreServiceState.ERROR;
    this.proxyState = ProxyState.ERROR;
    this.finishSession();
    this.publish(message);
  }

  private fileExists(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  private finishSession(): void {
    this.sessionTimer.finish(systemDateTime.getUptime(systemDateTime.TimeType.STARTUP));
  }

  // 无用户配置时也让 Core 保持可用，bootstrap 不允许开启系统代理。
  private async prepareBootstrapConfig(): Promise<string> {
    const workDir = `${this.context.filesDir}/core/work`;
    await this.ensureDirectory(workDir);
    const path = `${workDir}/bootstrap.yaml`;
    const file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, BOOTSTRAP_CORE_CONFIG);
    } finally {
      await fileIo.close(file);
    }
    return path;
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
