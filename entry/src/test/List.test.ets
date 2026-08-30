import localUnitTest from './LocalUnit.test';
import navigationModelsTest from './NavigationModels.test';
import protectProtocolTest from './ProtectProtocol.test';
import protectChannelServerTest from './ProtectChannelServer.test';
import coreRecoveryPolicyTest from './CoreRecoveryPolicy.test';
import vpnModelsTest from './VpnModels.test';
import coreControlProtocolTest from './CoreControlProtocol.test';
import runtimeModelsTest from './RuntimeModels.test';
import profileFeaturesTest from './ProfileFeatures.test';
import feedbackServiceTest from './FeedbackService.test';
import settingsModelsTest from './SettingsModels.test';
import notificationModelsTest from './NotificationModels.test';

export default function testsuite() {
  localUnitTest();
  navigationModelsTest();
  protectProtocolTest();
  protectChannelServerTest();
  coreRecoveryPolicyTest();
  vpnModelsTest();
  coreControlProtocolTest();
  runtimeModelsTest();
  profileFeaturesTest();
  feedbackServiceTest();
  settingsModelsTest();
  notificationModelsTest();
}
