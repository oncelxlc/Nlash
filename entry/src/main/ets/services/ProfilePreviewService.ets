import {
  decodeProxyDelayProgress,
  ProxyDelayProgress,
  ProxyDelayProgressListener
} from '../models/CoreControlProtocol';
import { CoreEvent, CoreEventType } from '../models/CoreModels';
import {
  GroupDelayResult,
  ProxySnapshot,
  RuntimeCommandResponse
} from '../models/RuntimeModels';
import { coreClient } from './CoreClient';

interface PreviewProxyPayload {
  configPath: string;
}

interface PreviewGroupDelayPayload {
  configPath: string;
  group: string;
  proxy: string;
  url: string;
  timeout: number;
  operationId: string;
}

interface CoreCommandEnvelope<T> {
  type: string;
  payload: T;
}

class ProfilePreviewService {
  async load(configPath: string): Promise<ProxySnapshot> {
    const payload: PreviewProxyPayload = { configPath: configPath };
    return this.execute<PreviewProxyPayload, ProxySnapshot>('previewProxySnapshot', payload);
  }

  async testGroup(configPath: string, group: string, proxy: string,
    url: string, operationId: string = '',
    progressListener: ProxyDelayProgressListener | undefined = undefined): Promise<GroupDelayResult> {
    const payload: PreviewGroupDelayPayload = {
      configPath: configPath,
      group: group,
      proxy: proxy,
      url: url,
      timeout: 5000,
      operationId: operationId
    };
    let unsubscribe: (() => void) | undefined = undefined;
    if (operationId.length > 0 && progressListener !== undefined) {
      unsubscribe = coreClient.subscribe((event: CoreEvent): void => {
        if (event.type !== CoreEventType.PROXY_DELAY_PROGRESS) {
          return;
        }
        const progress: ProxyDelayProgress | undefined = decodeProxyDelayProgress(event.message);
        if (progress?.operationId === operationId) {
          progressListener(progress);
        }
      });
    }
    try {
      return await this.execute<PreviewGroupDelayPayload, GroupDelayResult>('previewGroupDelay', payload);
    } finally {
      unsubscribe?.();
    }
  }

  private async execute<P, T>(type: string, payload: P): Promise<T> {
    const command: CoreCommandEnvelope<P> = { type: type, payload: payload };
    const raw = await coreClient.executeCommand(JSON.stringify(command));
    const response = JSON.parse(raw) as RuntimeCommandResponse<T>;
    if (!response.ok || response.data === undefined) {
      throw new Error(response.message.length > 0 ? response.message : response.code);
    }
    return response.data;
  }
}

export const profilePreviewService = new ProfilePreviewService();
