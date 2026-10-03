import { describe, expect, it } from '@ohos/hypium';
import { VpnService } from '../main/ets/services/VpnService';

export default function vpnServiceTest() {
  describe('vpnServiceStartup', () => {
    it('sharesOneStartupAndReusesTheRunningHost', 0, async () => {
      let calls = 0;
      let release: () => void = (): void => {};
      const service = new VpnService((): Promise<void> => {
        calls++;
        return new Promise<void>((resolve: () => void): void => { release = resolve; });
      });
      const first = service.ensureHost();
      const second = service.ensureHost();
      expect(first === second).assertTrue();
      expect(calls).assertEqual(1);
      release();
      await first;
      await service.ensureHost();
      expect(calls).assertEqual(1);
    });

    it('allowsRetryAfterFailedStartup', 0, async () => {
      let calls = 0;
      const service = new VpnService(async (): Promise<void> => {
        calls++;
        if (calls === 1) {
          throw new Error('startup failed');
        }
      });
      let failed = false;
      try {
        await service.ensureHost();
      } catch (error) {
        failed = true;
      }
      expect(failed).assertTrue();
      await service.ensureHost();
      expect(calls).assertEqual(2);
    });
  });
}
