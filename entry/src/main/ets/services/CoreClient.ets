import {
  coreState,
  coreVersion,
  executeCoreCommand,
  clearCoreEventListener,
  NativeCoreEvent,
  NativeCoreResult,
  NativeCoreStartOptions,
  startCore,
  setCoreEventListener,
  stopCore,
  validateConfig
} from 'proxy_core';
import {
  CoreClient,
  CoreErrorCode,
  CoreEvent,
  CoreEventListener,
  CoreEventType,
  CoreResult,
  CoreRuntimeState,
  CoreStartOptions
} from '../models/CoreModels';

const CORE_STATES: CoreRuntimeState[] = [
  CoreRuntimeState.STOPPED,
  CoreRuntimeState.VALIDATING,
  CoreRuntimeState.STARTING,
  CoreRuntimeState.RUNNING,
  CoreRuntimeState.STOPPING,
  CoreRuntimeState.FAILED
];

const CORE_ERRORS: CoreErrorCode[] = [
  CoreErrorCode.OK,
  CoreErrorCode.INVALID_ARGUMENT,
  CoreErrorCode.INVALID_STATE,
  CoreErrorCode.CONFIG_INVALID,
  CoreErrorCode.PROTECT_FAILED,
  CoreErrorCode.START_FAILED,
  CoreErrorCode.STOP_FAILED,
  CoreErrorCode.INTERNAL_ERROR,
  CoreErrorCode.UNAVAILABLE
];

const CORE_EVENT_TYPES: CoreEventType[] = [
  CoreEventType.LIFECYCLE,
  CoreEventType.LOG,
  CoreEventType.UNEXPECTED_EXIT,
  CoreEventType.PROTECT_FAILURE,
  CoreEventType.PROXY_DELAY_PROGRESS
];

class NativeCoreClient implements CoreClient {
  private listeners: Set<CoreEventListener> = new Set<CoreEventListener>();
  private readonly nativeEventListener = (event: NativeCoreEvent): void => {
    const state = event.state >= 0 && event.state < CORE_STATES.length ?
      CORE_STATES[event.state] : CoreRuntimeState.FAILED;
    const code = event.code >= 0 && event.code < CORE_ERRORS.length ?
      CORE_ERRORS[event.code] : CoreErrorCode.INTERNAL_ERROR;
    const type = event.type >= 0 && event.type < CORE_EVENT_TYPES.length ?
      CORE_EVENT_TYPES[event.type] : CoreEventType.LOG;
    const coreEvent: CoreEvent = {
      type: type,
      state: state,
      code: code,
      message: event.message
    };
    this.listeners.forEach((listener: CoreEventListener): void => listener(coreEvent));
  };

  getVersion(): string {
    return coreVersion();
  }

  async validateConfig(configPath: string): Promise<CoreResult> {
    this.publish(CoreRuntimeState.VALIDATING, CoreErrorCode.OK, 'Validating configuration');
    const result = this.mapResult(await validateConfig(configPath));
    this.publish(this.getState(), result.code, result.message);
    return result;
  }

  async start(options: CoreStartOptions): Promise<CoreResult> {
    this.publish(CoreRuntimeState.STARTING, CoreErrorCode.OK, 'Starting core');
    const nativeOptions: NativeCoreStartOptions = {
      configPath: options.configPath,
      workDir: options.workDir,
      tunFd: options.tunFd,
      mtu: options.mtu,
      protectSocketPath: options.protectSocketPath,
      generation: options.generation
    };
    const result = this.mapResult(await startCore(nativeOptions));
    this.publish(this.getState(), result.code, result.message);
    return result;
  }

  async stop(): Promise<void> {
    this.publish(CoreRuntimeState.STOPPING, CoreErrorCode.OK, 'Stopping core');
    const result = this.mapResult(await stopCore());
    this.publish(this.getState(), result.code, result.message);
    if (!result.ok) {
      throw new Error(`${result.code}: ${result.message}`);
    }
  }

  getState(): CoreRuntimeState {
    const value: number = coreState();
    return value >= 0 && value < CORE_STATES.length ? CORE_STATES[value] : CoreRuntimeState.FAILED;
  }

  subscribe(listener: CoreEventListener): () => void {
    if (this.listeners.size === 0) {
      setCoreEventListener(this.nativeEventListener);
    }
    this.listeners.add(listener);
    listener({
      type: CoreEventType.LIFECYCLE,
      state: this.getState(),
      code: CoreErrorCode.OK,
      message: ''
    });
    return (): void => {
      this.listeners.delete(listener);
      if (this.listeners.size === 0) {
        clearCoreEventListener();
      }
    };
  }

  executeCommand(command: string): Promise<string> {
    return executeCoreCommand(command);
  }

  private mapResult(result: NativeCoreResult): CoreResult {
    const code = result.code >= 0 && result.code < CORE_ERRORS.length ?
      CORE_ERRORS[result.code] : CoreErrorCode.INTERNAL_ERROR;
    return {
      ok: result.ok,
      code: code,
      message: result.message
    };
  }

  private publish(state: CoreRuntimeState, code: CoreErrorCode, message: string): void {
    const event: CoreEvent = {
      type: CoreEventType.LIFECYCLE,
      state: state,
      code: code,
      message: message
    };
    this.listeners.forEach((listener: CoreEventListener): void => listener(event));
  }
}

export const coreClient: CoreClient = new NativeCoreClient();
