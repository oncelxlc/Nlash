import { describe, expect, it } from '@ohos/hypium';
import {
  appendTrafficSample,
  ConnectionSnapshot,
  connectionTitle,
  DEFAULT_RUNTIME_MODE,
  formatBytes,
  formatSpeed,
  mergeGroupDelay,
  ProxyGroupSnapshot,
  pruneProxySelections,
  RuntimeMode,
  TrafficSample
} from '../main/ets/models/RuntimeModels';

export default function runtimeModelsTest() {
  describe('runtimeModels', () => {
    it('formatsTrafficValues', 0, () => {
      expect(formatBytes(0)).assertEqual('0 B');
      expect(formatBytes(1536)).assertEqual('1.5 KiB');
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

    it('keepsSixtyTrafficSamples', 0, () => {
      let history: TrafficSample[] = [];
      for (let index = 0; index < 65; index += 1) {
        history = appendTrafficSample(history, {
          timestamp: index, uploadSpeed: index, downloadSpeed: index * 2
        });
      }
      expect(history.length).assertEqual(60);
      expect(history[0].timestamp).assertEqual(5);
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
  });
}
