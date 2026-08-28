import { describe, expect, it } from '@ohos/hypium';
import {
  CoreRecoveryDecision,
  CoreRecoveryPolicy
} from '../main/ets/services/CoreRecoveryPolicy';

export default function coreRecoveryPolicyTest() {
  describe('coreRecoveryPolicy', () => {
    it('recoversOnceThenStops', 0, () => {
      const policy = new CoreRecoveryPolicy();
      expect(policy.onUnexpectedExit()).assertEqual(CoreRecoveryDecision.RECOVER);
      expect(policy.onUnexpectedExit()).assertEqual(CoreRecoveryDecision.IGNORE);
      policy.finishRecovery();
      expect(policy.onUnexpectedExit()).assertEqual(CoreRecoveryDecision.STOP);
    });

    it('resetStartsANewSession', 0, () => {
      const policy = new CoreRecoveryPolicy();
      expect(policy.onUnexpectedExit()).assertEqual(CoreRecoveryDecision.RECOVER);
      policy.finishRecovery();
      expect(policy.onUnexpectedExit()).assertEqual(CoreRecoveryDecision.STOP);
      policy.reset();
      expect(policy.onUnexpectedExit()).assertEqual(CoreRecoveryDecision.RECOVER);
    });
  });
}
