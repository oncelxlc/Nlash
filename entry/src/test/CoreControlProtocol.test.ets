import { describe, expect, it } from '@ohos/hypium';
import {
  CoreResponseBuffer,
  decodeCoreCommandEnvelope,
  decodeProxyDelayProgress,
  decodeCoreResponseEnvelope,
  encodeCoreCommandEnvelope,
  encodeProxyDelayProgress,
  encodeCoreResponseEnvelope,
  encodeCoreResponseChunks
} from '../main/ets/utils/CoreControlProtocol';
import { CORE_RESPONSE_CHUNK_LENGTH, MAX_CORE_COMMAND_LENGTH, MAX_CORE_RESPONSE_CHUNKS,
  MAX_CORE_RESPONSE_LENGTH } from '../main/ets/constants/CoreControlConstants';

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

    it('reassemblesLargeUnicodeResponsesOutOfOrderWithoutCompletingOnDuplicates', 0, () => {
      const response = JSON.stringify({ message: '日志🙂"\\'.repeat(15000) });
      const chunks = encodeCoreResponseChunks({ version: 1, requestId: 'request-large', response: response });
      const buffer = new CoreResponseBuffer();
      expect(chunks.length > 1).assertTrue();
      for (let index = chunks.length - 1; index >= 0; index--) {
        const chunk = chunks[index];
        expect(encodeURIComponent(chunk).replace(/%[0-9A-F]{2}/g, '_').length < 64 * 1024).assertTrue();
        const envelope = decodeCoreResponseEnvelope(chunk);
        expect(envelope !== undefined).assertTrue();
        if (envelope === undefined) { return; }
        const result = buffer.append(envelope);
        if (index === 0) {
          expect(result).assertEqual(response);
        } else {
          expect(result).assertUndefined();
          expect(buffer.append(envelope)).assertUndefined();
        }
      }
    });

    it('boundsEscapedChunksAndAcceptsTheMaximumResponse', 0, () => {
      const response = '\u0000'.repeat(MAX_CORE_RESPONSE_LENGTH);
      const chunks = encodeCoreResponseChunks({ version: 1, requestId: 'request-limit', response: response });
      const buffer = new CoreResponseBuffer();
      expect(chunks.length).assertEqual(MAX_CORE_RESPONSE_CHUNKS);
      let result: string | undefined;
      for (const chunk of chunks) {
        expect(chunk.length < 64 * 1024).assertTrue();
        const envelope = decodeCoreResponseEnvelope(chunk);
        expect(envelope !== undefined).assertTrue();
        if (envelope !== undefined) { result = buffer.append(envelope); }
      }
      expect(result).assertEqual(response);
      expect(new CoreResponseBuffer().append({ version: 1, requestId: 'request-small', response: 'ok' }))
        .assertEqual('ok');
    });

    it('rejectsInvalidChunkMetadataAndOversizedResponses', 0, () => {
      const prefix = '{"version":1,"requestId":"request-invalid","response":"x",';
      ['"chunkIndex":0', '"chunkCount":2', '"chunkIndex":-1,"chunkCount":2',
        '"chunkIndex":0.5,"chunkCount":2', '"chunkIndex":0,"chunkCount":1',
        '"chunkIndex":2,"chunkCount":2', `"chunkIndex":0,"chunkCount":${MAX_CORE_RESPONSE_CHUNKS + 1}`]
        .forEach((fields: string): void => {
          expect(decodeCoreResponseEnvelope(prefix + fields + '}')).assertUndefined();
        });
      expect(decodeCoreResponseEnvelope('null')).assertUndefined();
      expect(decodeCoreResponseEnvelope(encodeCoreResponseEnvelope({ version: 1, requestId: 'request-invalid',
        response: 'x'.repeat(CORE_RESPONSE_CHUNK_LENGTH + 1), chunkIndex: 0, chunkCount: 2 }))).assertUndefined();
      expect(decodeCoreResponseEnvelope(encodeCoreResponseEnvelope({ version: 1, requestId: 'request-invalid',
        response: 'x'.repeat(MAX_CORE_RESPONSE_LENGTH + 1) }))).assertUndefined();
    });

    it('rejectsConflictingChunksAndKeepsConcurrentRequestsSeparate', 0, () => {
      const first = new CoreResponseBuffer();
      const second = new CoreResponseBuffer();
      expect(first.append({ version: 1, requestId: 'request-first', response: 'a', chunkIndex: 0, chunkCount: 2 }))
        .assertUndefined();
      expect(second.append({ version: 1, requestId: 'request-second', response: 'b', chunkIndex: 1, chunkCount: 2 }))
        .assertUndefined();
      let conflict = false;
      try { first.append({ version: 1, requestId: 'request-first', response: 'c', chunkIndex: 0, chunkCount: 2 }); }
      catch (_error) { conflict = true; }
      expect(conflict).assertTrue();
      conflict = false;
      try { first.append({ version: 1, requestId: 'request-first', response: 'c', chunkIndex: 1, chunkCount: 3 }); }
      catch (_error) { conflict = true; }
      expect(conflict).assertTrue();
      expect(first.append({ version: 1, requestId: 'request-first', response: '1', chunkIndex: 1, chunkCount: 2 }))
        .assertEqual('a1');
      expect(second.append({ version: 1, requestId: 'request-second', response: '2', chunkIndex: 0, chunkCount: 2 }))
        .assertEqual('2b');
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
