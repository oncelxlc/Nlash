import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { CoreEvent, CoreEventType, CoreResult, CoreRuntimeState } from '../models/CoreModels';
import { ProxySelection, RuntimeCommandResponse } from '../models/RuntimeModels';
import { VpnState } from '../models/VpnModels';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { coreClient } from '../services/CoreClient';
import { coreControlServer } from '../services/CoreControlServer';
import { CoreRecoveryDecision, CoreRecoveryPolicy } from '../services/CoreRecoveryPolicy';
import { ProtectChannelServer, SocketProtector } from '../services/ProtectChannelServer';
import { publishVpnState } from '../services/VpnStatePublisher';

const DOMAIN = 0x4E4C;
const TAG = 'NlashProxyVpn';
const DEFAULT_MTU = 1400;

interface SelectProxyPayload {
  group: string;
  proxy: string;
}

interface SelectProxyCommand {
  type: string;
  payload: SelectProxyPayload;
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
  private startOperation: Promise<void> | undefined;
  private cleanupOperation: Promise<void> | undefined;
  private fatalOperation: Promise<void> | undefined;
  private unsubscribeCore: (() => void) | undefined;
  private recoveryPolicy: CoreRecoveryPolicy = new CoreRecoveryPolicy();
  private recoveryOperation: Promise<void> | undefined;
  private runtimeConfigPath: string = '';
  private requestedConfigPath: string = '';
  private runtimeProfileId: string = '';
  private runtimeSelections: ProxySelection[] = [];
  private runtimeMtu: number = DEFAULT_MTU;
  private controlReady: Promise<void> = Promise.resolve();

  onCreate(want: Want): void {
    this.destroying = false;
    const requestedConfigPath = want.parameters?.['configPath'];
    this.requestedConfigPath = typeof requestedConfigPath === 'string' ? requestedConfigPath : '';
    this.controlReady = coreControlServer.start();
    this.recoveryPolicy.reset();
    this.unsubscribeCore = coreClient.subscribe((event: CoreEvent): void => {
      if (event.type === CoreEventType.PROTECT_FAILURE) {
        const message = 'Outbound socket protect failed';
        publishVpnState(this.context.getApplicationContext(), VpnState.ERROR, message);
        this.handleFatalError(message);
      } else if (event.type === CoreEventType.UNEXPECTED_EXIT) {
        this.beginRecovery();
      }
    });
    hilog.info(DOMAIN, TAG, 'onCreate ability=%{public}s', want.abilityName ?? 'ProxyVpnAbility');
    publishVpnState(this.context.getApplicationContext(), VpnState.STARTING, 'Creating VPN connection');
    const operation = this.startVpn();
    this.startOperation = operation;
    operation.then((): void => {
      if (this.startOperation === operation) {
        this.startOperation = undefined;
      }
    }, (error: BusinessError): void => {
      if (this.startOperation === operation) {
        this.startOperation = undefined;
      }
      const message = this.describeError(error);
      hilog.error(DOMAIN, TAG, 'VPN start failed: %{public}s', message);
      publishVpnState(this.context.getApplicationContext(), VpnState.ERROR, message);
    });
  }

  onDestroy(): void {
    this.destroying = true;
    coreControlServer.stop();
    hilog.info(DOMAIN, TAG, 'onDestroy');
    this.cleanupAfterStart().then((): void => {
      hilog.info(DOMAIN, TAG, 'onDestroy cleanup completed');
    }, (error: BusinessError): void => {
      const message = this.describeError(error);
      hilog.error(DOMAIN, TAG, 'VPN cleanup failed: %{public}s', message);
      publishVpnState(this.context.getApplicationContext(), VpnState.ERROR, message);
    });
  }

  private async startVpn(): Promise<void> {
    await this.controlReady;
    await preferenceRepository.initialize(this.context.getApplicationContext());
    this.runtimeMtu = (await preferenceRepository.getAppSettings()).mtu;
    const connection = vpnExtension.createVpnConnection(this.context);
    this.vpnConnection = connection;

    const config: vpnExtension.VpnConfig = {
      addresses: [
        {
          address: {
            address: '172.19.0.1',
            family: 1
          },
          prefixLength: 30
        }
      ],
      routes: [
        {
          interface: 'vpn-tun',
          destination: {
            address: {
              address: '0.0.0.0',
              family: 1
            },
            prefixLength: 0
          },
          gateway: {
            address: '0.0.0.0',
            family: 1
          },
          hasGateway: false,
          isDefaultRoute: true
        }
      ],
      dnsAddresses: ['1.1.1.1'],
      mtu: this.runtimeMtu,
      isIPv4Accepted: true,
      isIPv6Accepted: false,
      isInternal: false,
      isBlocking: false
    };

    let fd: number;
    try {
      fd = await connection.create(config);
    } catch (error) {
      throw new Error(`VpnConnection.create failed: ${this.describeError(error as BusinessError)}`);
    }
    if (fd < 0) {
      throw new Error(`VpnConnection.create returned invalid fd=${fd}`);
    }
    this.tunFd = fd;
    hilog.info(DOMAIN, TAG, 'created TUN mtu=%{public}d', this.runtimeMtu);

    if (this.destroying) {
      await this.cleanup();
      return;
    }

    const generation = util.generateRandomUUID();
    const protectSocketPath = `${this.context.filesDir}/p-${generation.substring(0, 8)}.sock`;
    const protectChannel = new ProtectChannelServer(
      protectSocketPath,
      generation,
      new VpnSocketProtector(connection),
      (message: string): void => {
        hilog.error(DOMAIN, TAG, '%{public}s', message);
        publishVpnState(this.context.getApplicationContext(), VpnState.ERROR, message);
        this.handleFatalError(message);
      }
    );
    try {
      await protectChannel.start();
      this.protectChannel = protectChannel;
      hilog.info(DOMAIN, TAG, 'protect channel started generation=%{public}s', generation.substring(0, 8));
    } catch (error) {
      await this.cleanup();
      throw new Error(`Protect channel start failed: ${this.describeError(error as BusinessError)}`);
    }

    const configPath = await this.resolveRuntimeConfigPath();
    let hasConfig = false;
    try {
      hasConfig = fileIo.accessSync(configPath);
    } catch (error) {
      hasConfig = false;
    }
    if (!hasConfig) {
      await this.cleanup();
      throw new Error('活动配置文件不存在，请重新添加或选择配置');
    }
    this.runtimeConfigPath = configPath;
    this.runtimeProfileId = await preferenceRepository.getActiveProfileId();
    this.runtimeSelections = this.runtimeProfileId.length > 0 ?
      await preferenceRepository.getProxySelections(this.runtimeProfileId) : [];
    const validation = await coreClient.validateConfig(configPath);
    if (!validation.ok) {
      await this.cleanup();
      throw new Error(`Configuration validation failed: ${validation.code}`);
    }
    const workDir = `${this.context.filesDir}/core/work`;
    await this.ensureDirectory(workDir);
    const coreResult: CoreResult = await coreClient.start({
      configPath: configPath,
      workDir: workDir,
      tunFd: fd,
      mtu: this.runtimeMtu,
      protectSocketPath: protectSocketPath,
      generation: generation
    });
    if (!coreResult.ok || coreClient.getState() !== CoreRuntimeState.RUNNING) {
      await this.cleanup();
      throw new Error(`Core start failed: ${coreResult.code}`);
    }

    await this.applyRuntimeSelections();

    publishVpnState(this.context.getApplicationContext(), VpnState.CONNECTED, 'Mihomo and TUN connected');
  }

  private async cleanupAfterStart(): Promise<void> {
    const pendingStart = this.startOperation;
    if (pendingStart !== undefined) {
      try {
        await pendingStart;
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'start finished with error before cleanup: %{public}s',
          this.describeError(error as BusinessError));
      }
    }
    const pendingRecovery = this.recoveryOperation;
    if (pendingRecovery !== undefined) {
      try {
        await pendingRecovery;
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'recovery finished with error before cleanup');
      }
    }
    await this.cleanup();
  }

  private cleanup(): Promise<void> {
    if (this.cleanupOperation === undefined) {
      const operation = this.cleanupInternal();
      this.cleanupOperation = operation;
      operation.then((): void => {
        if (this.cleanupOperation === operation) {
          this.cleanupOperation = undefined;
        }
      }, (): void => {
        if (this.cleanupOperation === operation) {
          this.cleanupOperation = undefined;
        }
      });
    }
    return this.cleanupOperation;
  }

  private async cleanupInternal(): Promise<void> {
    if (coreClient.getState() !== CoreRuntimeState.STOPPED) {
      try {
        await this.withTimeout(coreClient.stop(), 5000);
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'core stop failed: %{public}s', this.describeError(error as BusinessError));
      }
    }
    this.tunFd = -1;

    const protectChannel = this.protectChannel;
    this.protectChannel = undefined;
    if (protectChannel !== undefined) {
      await protectChannel.stop();
      hilog.info(DOMAIN, TAG, 'protect channel stopped');
    }

    const connection = this.vpnConnection;
    this.vpnConnection = undefined;
    if (connection !== undefined) {
      try {
        await connection.destroy();
      } catch (error) {
        throw new Error(`VpnConnection.destroy failed: ${this.describeError(error as BusinessError)}`);
      }
      hilog.info(DOMAIN, TAG, 'VPN connection destroyed');
    }
    const unsubscribeCore = this.unsubscribeCore;
    this.unsubscribeCore = undefined;
    if (unsubscribeCore !== undefined) {
      unsubscribeCore();
    }
    publishVpnState(this.context.getApplicationContext(), VpnState.DISCONNECTED, 'VPN connection destroyed');
    this.runtimeConfigPath = '';
    this.runtimeProfileId = '';
    this.runtimeSelections = [];
  }

  private handleFatalError(message: string): void {
    if (this.fatalOperation !== undefined || this.destroying) {
      return;
    }
    const operation = this.cleanup();
    this.fatalOperation = operation;
    operation.then((): void => {
      this.fatalOperation = undefined;
    }, (): void => {
      this.fatalOperation = undefined;
    });
    hilog.error(DOMAIN, TAG, 'fatal runtime error: %{public}s', message);
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
      publishVpnState(this.context.getApplicationContext(), VpnState.ERROR,
        'Core exited again after one recovery');
      this.handleFatalError('Core exited again after one recovery');
      return;
    }
    const operation = this.recoverCoreOnce();
    this.recoveryOperation = operation;
    operation.then((): void => {
      if (this.recoveryOperation === operation) {
        this.recoveryOperation = undefined;
      }
      this.recoveryPolicy.finishRecovery();
    }, (): void => {
      if (this.recoveryOperation === operation) {
        this.recoveryOperation = undefined;
      }
      this.recoveryPolicy.finishRecovery();
      this.handleFatalError('Core recovery failed');
    });
  }

  private async recoverCoreOnce(): Promise<void> {
    publishVpnState(this.context.getApplicationContext(), VpnState.STARTING,
      'Rebuilding protect generation for one recovery');
    const previousChannel = this.protectChannel;
    this.protectChannel = undefined;
    if (previousChannel !== undefined) {
      await previousChannel.stop();
    }
    if (this.destroying || this.vpnConnection === undefined || this.tunFd < 0) {
      throw new Error('VPN is no longer available for recovery');
    }

    const generation = util.generateRandomUUID();
    const socketPath = `${this.context.filesDir}/p-${generation.substring(0, 8)}.sock`;
    const channel = new ProtectChannelServer(
      socketPath,
      generation,
      new VpnSocketProtector(this.vpnConnection),
      (message: string): void => {
        publishVpnState(this.context.getApplicationContext(), VpnState.ERROR, message);
        this.handleFatalError(message);
      }
    );
    await channel.start();
    if (this.destroying) {
      await channel.stop();
      throw new Error('VPN is stopping during recovery');
    }
    this.protectChannel = channel;

    const configPath = this.runtimeConfigPath;
    if (configPath.length === 0) {
      throw new Error('Runtime configuration is unavailable for recovery');
    }
    const validation = await coreClient.validateConfig(configPath);
    if (!validation.ok) {
      throw new Error(`Recovery validation failed: ${validation.code}`);
    }
    const workDir = `${this.context.filesDir}/core/work`;
    await this.ensureDirectory(workDir);
    const result = await coreClient.start({
      configPath: configPath,
      workDir: workDir,
      tunFd: this.tunFd,
      mtu: this.runtimeMtu,
      protectSocketPath: socketPath,
      generation: generation
    });
    if (!result.ok || coreClient.getState() !== CoreRuntimeState.RUNNING) {
      throw new Error(`Recovery start failed: ${result.code}`);
    }
    await this.applyRuntimeSelections();
    publishVpnState(this.context.getApplicationContext(), VpnState.CONNECTED,
      'Core recovered once with a new protect generation');
  }

  private withTimeout(operation: Promise<void>, timeoutMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void, reject: (reason: Error) => void): void => {
      const timeoutId = setTimeout((): void => {
        reject(new Error('Core stop timed out'));
      }, timeoutMs);
      operation.then((): void => {
        clearTimeout(timeoutId);
        resolve();
      }, (error: Error): void => {
        clearTimeout(timeoutId);
        reject(error);
      });
    });
  }

  private async resolveRuntimeConfigPath(): Promise<string> {
    if (this.requestedConfigPath.length > 0) {
      return this.requestedConfigPath;
    }
    await preferenceRepository.initialize(this.context.getApplicationContext());
    const activeProfilePath = await preferenceRepository.getActiveProfilePath();
    if (activeProfilePath.length > 0) {
      return activeProfilePath;
    }
    throw new Error('Active profile configuration is unavailable');
  }

  private async applyRuntimeSelections(): Promise<void> {
    for (let index = 0; index < this.runtimeSelections.length; index += 1) {
      const selection = this.runtimeSelections[index];
      const payload: SelectProxyPayload = { group: selection.group, proxy: selection.proxy };
      const command: SelectProxyCommand = { type: 'selectProxy', payload: payload };
      try {
        const raw = await coreClient.executeCommand(JSON.stringify(command));
        const response = JSON.parse(raw) as RuntimeCommandResponse<Object>;
        if (!response.ok) {
          hilog.warn(DOMAIN, TAG, 'Skipped stale proxy preselection');
        }
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'Failed to apply proxy preselection');
      }
    }
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

  private describeError(error: BusinessError): string {
    const code = error.code === undefined ? 'unknown' : error.code.toString();
    return `code=${code}, message=${error.message}`;
  }
}
