import { describe, expect, it } from '@ohos/hypium';
import {
  decodeCoreCommandEnvelope,
  decodeProxyDelayProgress,
  decodeCoreResponseEnvelope,
  encodeCoreCommandEnvelope,
  encodeProxyDelayProgress,
  encodeCoreResponseEnvelope
} from '../main/ets/utils/CoreControlProtocol';
import { MAX_CORE_COMMAND_LENGTH } from '../main/ets/constants/CoreControlConstants';

export default function coreControlProtocolTest() {
  describe('coreControlProtocol', () => {
    it('roundTripsCommandAndResponse', 0, () => {
      const command = decodeCoreCommandEnvelope(encodeCoreCommandEnvelope({
        version: 1,
        requestId: 'request-1234',
        command: '{"type":"dashboardSnapshot"}'
      }));
      const response = decodeCoreResponseEnvelope(encodeCoreResponseEnvelope({
        version: 1,
        requestId: 'request-1234',
        response: '{"ok":true,"code":"OK","message":""}'
      }));

      expect(command?.requestId).assertEqual('request-1234');
      expect(response?.response.includes('"ok":true')).assertTrue();
    });

    it('rejectsMalformedAndOversizeCommand', 0, () => {
      expect(decodeCoreCommandEnvelope('{')).assertUndefined();
      expect(decodeCoreCommandEnvelope('{"version":2,"requestId":"request-1234","command":"x"}'))
        .assertUndefined();
      const oversized = 'x'.repeat(MAX_CORE_COMMAND_LENGTH + 1);
      expect(decodeCoreCommandEnvelope(JSON.stringify({
        version: 1,
        requestId: 'request-1234',
        command: oversized
      }))).assertUndefined();
    });

    it('validatesProxyDelayProgress', 0, () => {
      const progress = decodeProxyDelayProgress(encodeProxyDelayProgress({
        operationId: 'operation-1234', group: 'Auto', proxy: 'Node A', delay: 86, alive: true
      }));
      expect(progress?.proxy).assertEqual('Node A');
      expect(progress?.delay).assertEqual(86);
      expect(decodeProxyDelayProgress('{')).assertUndefined();
      expect(decodeProxyDelayProgress(JSON.stringify({
        operationId: 'short', group: 'Auto', proxy: 'Node A', delay: 86, alive: true
      }))).assertUndefined();
      expect(decodeProxyDelayProgress(JSON.stringify({
        operationId: 'operation-1234', group: 'Auto', proxy: 'Node A', delay: -2, alive: false
      }))).assertUndefined();
    });
  });
}
