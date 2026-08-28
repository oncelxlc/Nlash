import { describe, expect, it } from '@ohos/hypium';
import {
  ProtectFailureCode,
  ProtectRequestCoordinator,
  SocketProtector
} from '../main/ets/services/ProtectChannelServer';
import {
  PROTECT_PROTOCOL_VERSION,
  ProtectMessageType,
  ProtectRequest
} from '../main/ets/services/ProtectProtocol';

class RecordingProtector implements SocketProtector {
  protectedFd: number = -1;
  shouldFail: boolean = false;

  async protect(socketFd: number): Promise<void> {
    if (this.shouldFail) {
      throw new Error('expected failure');
    }
    this.protectedFd = socketFd;
  }
}

function request(requestId: number, generation: string = 'generation-1'): ProtectRequest {
  return {
    version: PROTECT_PROTOCOL_VERSION,
    type: ProtectMessageType.REQUEST,
    requestId: requestId,
    generation: generation,
    fd: 51
  };
}

export default function protectChannelServerTest() {
  describe('protectRequestCoordinator', () => {
    it('protectsAnActiveGenerationSocket', 0, async () => {
      const protector = new RecordingProtector();
      const coordinator = new ProtectRequestCoordinator('generation-1', protector);
      const ack = await coordinator.handle(request(1));
      expect(ack.ok).assertTrue();
      expect(protector.protectedFd).assertEqual(51);
    });

    it('rejectsStaleGenerations', 0, async () => {
      const coordinator = new ProtectRequestCoordinator('generation-1', new RecordingProtector());
      const ack = await coordinator.handle(request(1, 'old-generation'));
      expect(ack.ok).assertFalse();
      expect(ack.errorCode).assertEqual(ProtectFailureCode.STALE_GENERATION);
    });

    it('rejectsDuplicateRequestIds', 0, async () => {
      const coordinator = new ProtectRequestCoordinator('generation-1', new RecordingProtector());
      expect((await coordinator.handle(request(1))).ok).assertTrue();
      const duplicate = await coordinator.handle(request(1));
      expect(duplicate.ok).assertFalse();
      expect(duplicate.errorCode).assertEqual(ProtectFailureCode.DUPLICATE_REQUEST);
    });

    it('mapsProtectFailuresToAck', 0, async () => {
      const protector = new RecordingProtector();
      protector.shouldFail = true;
      const coordinator = new ProtectRequestCoordinator('generation-1', protector);
      const ack = await coordinator.handle(request(1));
      expect(ack.ok).assertFalse();
      expect(ack.errorCode).assertEqual(ProtectFailureCode.PROTECT_FAILED);
    });
  });
}
