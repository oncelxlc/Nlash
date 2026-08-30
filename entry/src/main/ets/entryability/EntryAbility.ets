import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { Profile } from '../models/ProfileModels';
import { vpnService } from '../services/VpnService';
import { profileStore } from '../stores/ProfileStore';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    vpnService.initialize(this.context.getApplicationContext());
    const profileOperation = profileStore.initialize(this.context);
    profileOperation.catch((): void => {
      hilog.error(DOMAIN, 'NlashProfile', 'Profile data initialization failed');
    });
    runtimeStore.initialize();
    const settingsOperation = settingsStore.initialize(this.context.getApplicationContext());
    settingsOperation.catch((): void => {
      hilog.error(DOMAIN, 'NlashSettings', 'Settings initialization failed');
    });
    Promise.all([profileOperation, settingsOperation]).then((): void => {
      const snapshot = profileStore.getSnapshot();
      const active = snapshot.profiles.find((profile: Profile): boolean =>
        profile.id === snapshot.activeProfileId);
      if (active === undefined) {
        vpnService.ensureHost().catch((): void => {
          hilog.error(DOMAIN, 'NlashCore', 'Core host initialization failed');
        });
        return;
      }
      const signature = `${active.id}:${active.localPath}:${active.updatedAt}`;
      vpnService.applyProfile(active.id, active.localPath, signature).catch((): void => {
        hilog.error(DOMAIN, 'NlashCore', 'Core profile initialization failed');
      });
    });
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    profileStore.shutdown();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    profileStore.onForeground();
    runtimeStore.setForeground(true);
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    runtimeStore.setForeground(false);
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
