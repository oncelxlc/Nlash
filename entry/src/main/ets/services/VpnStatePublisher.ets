import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  encodeVpnStateEnvelope,
  VPN_BUNDLE_NAME,
  VPN_STATE_COMMON_EVENT,
  VPN_STATE_EVENT,
  VpnState,
  VpnStateEvent
} from '../models/VpnModels';

const DOMAIN = 0x4E4C;
const TAG = 'NlashVpnState';
const SOURCE_ID: string = util.generateRandomUUID();
const SOURCE_STARTED_AT: number = Date.now();
let nextSequence: number = 0;

export function publishVpnState(
  applicationContext: common.ApplicationContext,
  state: VpnState,
  message: string = ''
): void {
  const event: VpnStateEvent = { state, message };
  hilog.info(DOMAIN, TAG, 'state=%{public}s message=%{public}s', state, message);
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
