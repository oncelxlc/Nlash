import { describe, expect, it } from '@ohos/hypium';
import {
  encodeProtectMessage,
  PROTECT_MAX_PAYLOAD_BYTES,
  PROTECT_PROTOCOL_VERSION,
  ProtectFrameDecoder,
  ProtectMessageType,
  ProtectProtocolError,
  ProtectProtocolErrorCode,
  ProtectRequest,
  ProtectWireMessage
} from '../main/ets/services/ProtectProtocol';

function request(requestId: number = 7): ProtectRequest {
  return {
    version: PROTECT_PROTOCOL_VERSION,
    type: ProtectMessageType.REQUEST,
    requestId: requestId,
    generation: 'generation-1',
    fd: 42
  };
}

function join(first: ArrayBuffer, second: ArrayBuffer): ArrayBuffer {
  const left = new Uint8Array(first);
  const right = new Uint8Array(second);
  const joined = new Uint8Array(left.byteLength + right.byteLength);
  joined.set(left, 0);
  joined.set(right, left.byteLength);
  return joined.buffer;
}

function slice(value: ArrayBuffer, start: number, end?: number): ArrayBuffer {
  return new Uint8Array(value).slice(start, end).buffer;
}

function framePayload(payload: Uint8Array): ArrayBuffer {
  const frame = new Uint8Array(4 + payload.byteLength);
  frame[0] = (payload.byteLength >>> 24) & 0xFF;
  frame[1] = (payload.byteLength >>> 16) & 0xFF;
  frame[2] = (payload.byteLength >>> 8) & 0xFF;
  frame[3] = payload.byteLength & 0xFF;
  frame.set(payload, 4);
  return frame.buffer;
}

export default function protectProtocolTest() {
  describe('protectProtocol', () => {
    it('roundTripsARequest', 0, () => {
      const decoded = new ProtectFrameDecoder().append(encodeProtectMessage(request()));
      expect(decoded.length).assertEqual(1);
      expect(decoded[0].type).assertEqual(ProtectMessageType.REQUEST);
      expect(decoded[0].requestId).assertEqual(7);
      expect(decoded[0].generation).assertEqual('generation-1');
      expect(decoded[0].fd).assertEqual(42);
    });

    it('buffersFragmentedFrames', 0, () => {
      const frame = encodeProtectMessage(request());
      const decoder = new ProtectFrameDecoder();
      expect(decoder.append(slice(frame, 0, 2)).length).assertEqual(0);
      expect(decoder.append(slice(frame, 2, 9)).length).assertEqual(0);
      const decoded = decoder.append(slice(frame, 9));
      expect(decoded.length).assertEqual(1);
      expect(decoded[0].requestId).assertEqual(7);
    });

    it('decodesCoalescedFrames', 0, () => {
      const frames = join(encodeProtectMessage(request(1)), encodeProtectMessage(request(2)));
      const decoded = new ProtectFrameDecoder().append(frames);
      expect(decoded.length).assertEqual(2);
      expect(decoded[0].requestId).assertEqual(1);
      expect(decoded[1].requestId).assertEqual(2);
    });

    it('rejectsOversizedFrames', 0, () => {
      const invalid = new Uint8Array(4);
      const length = PROTECT_MAX_PAYLOAD_BYTES + 1;
      invalid[0] = (length >>> 24) & 0xFF;
      invalid[1] = (length >>> 16) & 0xFF;
      invalid[2] = (length >>> 8) & 0xFF;
      invalid[3] = length & 0xFF;
      try {
        new ProtectFrameDecoder().append(invalid.buffer as ArrayBuffer);
        expect(false).assertTrue();
      } catch (error) {
        const protocolError = error as ProtectProtocolError;
        expect(protocolError.code).assertEqual(ProtectProtocolErrorCode.INVALID_LENGTH);
      }
    });

    it('rejectsUnsupportedVersions', 0, () => {
      const invalid: ProtectWireMessage = request();
      invalid.version = 2;
      try {
        encodeProtectMessage(invalid);
        expect(false).assertTrue();
      } catch (error) {
        const protocolError = error as ProtectProtocolError;
        expect(protocolError.code).assertEqual(ProtectProtocolErrorCode.UNSUPPORTED_VERSION);
      }
    });

    it('rejectsInvalidJson', 0, () => {
      const payload = new Uint8Array([0x7B, 0x6E, 0x6F, 0x70, 0x65]);
      try {
        new ProtectFrameDecoder().append(framePayload(payload));
        expect(false).assertTrue();
      } catch (error) {
        const protocolError = error as ProtectProtocolError;
        expect(protocolError.code).assertEqual(ProtectProtocolErrorCode.INVALID_JSON);
      }
    });

    it('rejectsInvalidUtf8', 0, () => {
      const payload = new Uint8Array([0xC3, 0x28]);
      try {
        new ProtectFrameDecoder().append(framePayload(payload));
        expect(false).assertTrue();
      } catch (error) {
        const protocolError = error as ProtectProtocolError;
        expect(protocolError.code).assertEqual(ProtectProtocolErrorCode.INVALID_UTF8);
      }
    });
  });
}
