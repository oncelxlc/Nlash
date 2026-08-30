import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CoreServiceState,
  encodeVpnStateEnvelope,
  ProxyState,
  VPN_BUNDLE_NAME,
  VPN_STATE_COMMON_EVENT,
  VPN_STATE_EVENT,
  VpnStateEvent,
  vpnStateFromProxyState
} from '../models/VpnModels';

const DOMAIN = 0x4E4C;
const TAG = 'NlashVpnState';
const SOURCE_ID: string = util.generateRandomUUID();
const SOURCE_STARTED_AT: number = Date.now();
let nextSequence: number = 0;

export function publishVpnState(
  applicationContext: common.ApplicationContext,
  coreState: CoreServiceState,
  proxyState: ProxyState,
  message: string = '',
  profileId: string = '',
  profileSignature: string = ''
): void {
  const event: VpnStateEvent = {
    state: vpnStateFromProxyState(proxyState),
    coreState: coreState,
    proxyState: proxyState,
    profileId: profileId,
    profileSignature: profileSignature,
    message: message
  };
  hilog.info(DOMAIN, TAG, 'core=%{public}s proxy=%{public}s message=%{public}s',
    coreState, proxyState, message);
  applicationContext.eventHub.emit(VPN_STATE_EVENT, event);
  try {
    commonEventManager.publish(VPN_STATE_COMMON_EVENT, {
      bundleName: VPN_BUNDLE_NAME,
      data: encodeVpnStateEnvelope({
        sourceId: SOURCE_ID,
        sourceStartedAt: SOURCE_STARTED_AT,
        sequence: ++nextSequence,
        event: event
      })
    }, (error: BusinessError): void => {
      if (error) {
        hilog.error(DOMAIN, TAG, 'cross-process publish failed code=%{public}d', error.code);
      }
    });
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'cross-process publish threw');
  }
}
