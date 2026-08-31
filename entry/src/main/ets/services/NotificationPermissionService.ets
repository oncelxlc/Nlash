import { common } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { shouldRequestNotificationPermission } from '../utils/NotificationUtils';
import { VPN_NOTIFICATION_REFRESH_EVENT } from '../constants/NotificationConstants';
import { VPN_BUNDLE_NAME } from '../constants/VpnConstants';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { feedbackService } from './FeedbackService';

const DOMAIN = 0x4E4C;
const TAG = 'NlashNotifyPermission';

class NotificationPermissionService {
  private operation: Promise<boolean> | undefined;

  ensurePermission(context: common.UIAbilityContext): Promise<boolean> {
    if (this.operation === undefined) {
      const operation = this.ensurePermissionInternal(context);
      this.operation = operation;
      operation.then((): void => {
        if (this.operation === operation) {
          this.operation = undefined;
        }
      }, (): void => {
        if (this.operation === operation) {
          this.operation = undefined;
        }
      });
    }
    return this.operation;
  }

  private async ensurePermissionInternal(context: common.UIAbilityContext): Promise<boolean> {
    try {
      await preferenceRepository.initialize(context.getApplicationContext());
      const enabled = await notificationManager.isNotificationEnabled();
      if (enabled) {
        this.publishRefresh();
        return true;
      }
      const requested = await preferenceRepository.getNotificationPermissionRequested();
      if (!shouldRequestNotificationPermission(enabled, requested)) {
        return false;
      }
      await preferenceRepository.setNotificationPermissionRequested();
      await notificationManager.requestEnableNotification(context);
      const granted = await notificationManager.isNotificationEnabled();
      if (granted) {
        this.publishRefresh();
        return true;
      }
      feedbackService.warning('通知权限未开启，代理可继续运行，但通知栏状态不可用');
      return false;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'notification permission request failed');
      feedbackService.warning('通知权限未开启，代理可继续运行，但通知栏状态不可用');
      return false;
    }
  }

  private publishRefresh(): void {
    try {
      commonEventManager.publish(VPN_NOTIFICATION_REFRESH_EVENT, {
        bundleName: VPN_BUNDLE_NAME
      }, (error: BusinessError): void => {
        if (error) {
          hilog.warn(DOMAIN, TAG, 'notification refresh publish failed code=%{public}d', error.code);
        }
      });
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'notification refresh publish threw');
    }
  }
}

export const notificationPermissionService = new NotificationPermissionService();
