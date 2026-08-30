import { describe, expect, it } from '@ohos/hypium';
import {
  appendTrafficSample,
  ConnectionSnapshot,
  connectionTitle,
  DEFAULT_RUNTIME_MODE,
  formatBytes,
  formatBytesParts,
  formatSpeed,
  failPendingGroupDelay,
  mergeGroupDelay,
  preserveTestedProxyDelays,
  proxyDelayLabel,
  proxyNodeRenderKey,
  ProxyGroupSnapshot,
  pruneProxySelections,
  resetGroupDelay,
  RuntimeRequestMerger,
  RuntimeMode,
  TrafficSample
} from '../main/ets/models/RuntimeModels';

export default function runtimeModelsTest() {
  describe('runtimeModels', () => {
    it('formatsTrafficValues', 0, () => {
      expect(formatBytes(0)).assertEqual('0 B');
      expect(formatBytes(1536)).assertEqual('1.5 KiB');
      expect(formatBytesParts(1536).value).assertEqual('1.5');
      expect(formatBytesParts(1536).unit).assertEqual('KiB');
      expect(formatSpeed(1024)).assertEqual('1.0 KiB/s');
    });

    it('defaultsRuntimeModeToRule', 0, () => {
      expect(DEFAULT_RUNTIME_MODE).assertEqual(RuntimeMode.RULE);
    });

    it('prefersHostForConnectionTitle', 0, () => {
      const base: ConnectionSnapshot = {
        id: 'id', network: 'tcp', type: 'HTTP', host: 'example.com', destination: '1.1.1.1:443', source: '',
        process: '', start: 0, upload: 0, download: 0, chains: [], rule: '', rulePayload: ''
      };
      expect(connectionTitle(base)).assertEqual('example.com');
      base.host = '';
      expect(connectionTitle(base)).assertEqual('1.1.1.1:443');
    });

    it('keepsTrafficSamplesFromTheLastSixtySeconds', 0, () => {
      let history: TrafficSample[] = [];
      for (let index = 0; index <= 12; index += 1) {
        history = appendTrafficSample(history, {
          timestamp: index * 5000, uploadSpeed: index, downloadSpeed: index * 2
        });
      }
      history = appendTrafficSample(history, {
        timestamp: 60001, uploadSpeed: 13, downloadSpeed: 26
      });
      expect(history.length).assertEqual(13);
      expect(history[0].timestamp).assertEqual(5000);
      expect(history[history.length - 1].timestamp).assertEqual(60001);
    });

    it('mergesOverlappingRefreshRequests', 0, async () => {
      const merger = new RuntimeRequestMerger();
      let requestCount = 0;
      let release: () => void = (): void => {};
      const first = merger.run((): Promise<void> => {
        requestCount += 1;
        return new Promise<void>((resolve: () => void): void => {
          release = resolve;
        });
      });
      const second = merger.run(async (): Promise<void> => {
        requestCount += 1;
      });
      expect(first === second).assertTrue();
      expect(requestCount).assertEqual(1);
      release();
      await first;
      await merger.run(async (): Promise<void> => {
        requestCount += 1;
      });
      expect(requestCount).assertEqual(2);
    });

    it('mergesDelayAndPrunesStaleSelections', 0, () => {
      const groups: ProxyGroupSnapshot[] = [{
        name: 'Auto', type: 'Selector', selected: 'A', selectable: true, hidden: false,
        nodes: [
          { name: 'A', type: 'Vless', alive: false, tested: false, delay: 0, udp: true },
          { name: 'B', type: 'Vless', alive: false, tested: false, delay: 0, udp: false }
        ]
      }];
      const merged = mergeGroupDelay(groups, 'Auto', [{ proxy: 'B', delay: 88, alive: true }]);
      expect(merged[0].nodes[1].tested).assertTrue();
      expect(merged[0].nodes[1].delay).assertEqual(88);
      const selections = pruneProxySelections(groups, [
        { group: 'Auto', proxy: 'A' }, { group: 'Missing', proxy: 'B' }
      ]);
      expect(selections.length).assertEqual(1);
      expect(selections[0].proxy).assertEqual('A');
    });

    it('tracksProgressiveDelayStates', 0, () => {
      const groups: ProxyGroupSnapshot[] = [{
        name: 'Auto', type: 'Selector', selected: 'A', selectable: true, hidden: false,
        nodes: [
          { name: 'A', type: 'Vless', alive: true, tested: true, delay: 42, udp: true },
          { name: 'B', type: 'Vless', alive: true, tested: true, delay: 64, udp: false }
        ]
      }];
      const reset = resetGroupDelay(groups, 'Auto');
      expect(proxyDelayLabel(reset[0].nodes[0], true)).assertEqual('…');
      expect(proxyDelayLabel(reset[0].nodes[0], false)).assertEqual('⚡');
      const partial = mergeGroupDelay(reset, 'Auto', [{ proxy: 'B', delay: 88, alive: true }]);
      expect(proxyDelayLabel(partial[0].nodes[1], false)).assertEqual('88ms');
      expect(proxyNodeRenderKey(partial[0].nodes[1]) === proxyNodeRenderKey(reset[0].nodes[1])).assertFalse();
      const failed = failPendingGroupDelay(partial, 'Auto');
      expect(proxyDelayLabel(failed[0].nodes[0], false)).assertEqual('Error');
      expect(proxyDelayLabel(failed[0].nodes[1], false)).assertEqual('88ms');
      const refreshed: ProxyGroupSnapshot[] = [{
        name: 'Auto', type: 'Selector', selected: 'A', selectable: true, hidden: false,
        nodes: [
          { name: 'A', type: 'Vless', alive: false, tested: false, delay: 0, udp: true },
          { name: 'B', type: 'Vless', alive: false, tested: false, delay: 0, udp: false }
        ]
      }];
      const preserved = preserveTestedProxyDelays(refreshed, failed);
      expect(proxyDelayLabel(preserved[0].nodes[0], false)).assertEqual('Error');
      expect(proxyDelayLabel(preserved[0].nodes[1], false)).assertEqual('88ms');
    });
  });
}
