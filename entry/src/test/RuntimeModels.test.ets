import { describe, expect, it } from '@ohos/hypium';
import {
  appendTrafficSample,
  connectionTitle,
  formatBytes,
  formatBytesParts,
  formatSpeed,
  failPendingGroupDelay,
  mergeGroupDelay,
  mergeProxyTrafficSnapshot,
  preserveTestedProxyDelays,
  ProxyDelayOperationRegistry,
  proxyDelayLabel,
  proxyNodeRenderKey,
  pruneProxySelections,
  resetGroupDelay,
  resolveSelectedProxyGroup,
  RuntimeRequestMerger,
  visibleProxyGroups
} from '../main/ets/utils/RuntimeUtils';
import { ConnectionSnapshot, DashboardSnapshot, ProxyGroupSnapshot, RuntimeMode, TrafficSample } from '../main/ets/model/RuntimeModels';
import { DEFAULT_RUNTIME_MODE } from '../main/ets/constants/RuntimeConstants';

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

    it('countsOnlyConnectedProxyIntervalsAndFreezesStoppedTraffic', 0, () => {
      const baseline: DashboardSnapshot = {
        mode: RuntimeMode.RULE, uploadSpeed: 10, downloadSpeed: 20,
        uploadTotal: 100, downloadTotal: 200, memoryBytes: 1024, connectionCount: 1
      };
      const idle = mergeProxyTrafficSnapshot(baseline, undefined, undefined);
      expect(idle.uploadSpeed).assertEqual(0);
      expect(idle.downloadSpeed).assertEqual(0);
      expect(idle.uploadTotal).assertEqual(0);
      expect(idle.downloadTotal).assertEqual(0);

      const active: DashboardSnapshot = {
        mode: RuntimeMode.GLOBAL, uploadSpeed: 30, downloadSpeed: 60,
        uploadTotal: 130, downloadTotal: 260, memoryBytes: 2048, connectionCount: 2
      };
      const connected = mergeProxyTrafficSnapshot(active, idle, baseline);
      expect(connected.uploadSpeed).assertEqual(30);
      expect(connected.downloadSpeed).assertEqual(60);
      expect(connected.uploadTotal).assertEqual(30);
      expect(connected.downloadTotal).assertEqual(60);
      expect(connected.mode).assertEqual(RuntimeMode.GLOBAL);
      expect(connected.memoryBytes).assertEqual(2048);
      expect(connected.connectionCount).assertEqual(2);

      const inactive: DashboardSnapshot = {
        mode: RuntimeMode.RULE, uploadSpeed: 100, downloadSpeed: 200,
        uploadTotal: 1000, downloadTotal: 2000, memoryBytes: 1024, connectionCount: 1
      };
      const paused = mergeProxyTrafficSnapshot(inactive, connected, undefined);
      expect(paused.uploadTotal).assertEqual(30);
      expect(paused.downloadTotal).assertEqual(60);
      expect(paused.uploadSpeed).assertEqual(0);
      expect(paused.downloadSpeed).assertEqual(0);
      const resumed = mergeProxyTrafficSnapshot(inactive, paused, undefined);
      expect(resumed.uploadTotal).assertEqual(30);
      expect(resumed.downloadTotal).assertEqual(60);
      const next: DashboardSnapshot = {
        mode: RuntimeMode.RULE, uploadSpeed: 10, downloadSpeed: 20,
        uploadTotal: 1010, downloadTotal: 2020, memoryBytes: 1024, connectionCount: 1
      };
      const continued = mergeProxyTrafficSnapshot(next, resumed, inactive);
      expect(continued.uploadTotal).assertEqual(40);
      expect(continued.downloadTotal).assertEqual(80);
      const reset = mergeProxyTrafficSnapshot(baseline, connected, active);
      expect(reset.uploadTotal).assertEqual(30);
      expect(reset.downloadTotal).assertEqual(60);
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

    it('doesNotBlockDashboardRefreshWhenDetailRefreshIsPending', 0, async () => {
      const dashboardMerger = new RuntimeRequestMerger();
      const detailMerger = new RuntimeRequestMerger();
      let dashboardRequestCount = 0;
      let detailRequestCount = 0;
      let releaseDetail: () => void = (): void => {};
      const detail = detailMerger.run((): Promise<void> => {
        detailRequestCount += 1;
        return new Promise<void>((resolve: () => void): void => {
          releaseDetail = resolve;
        });
      });
      await dashboardMerger.run(async (): Promise<void> => {
        dashboardRequestCount += 1;
      });
      await dashboardMerger.run(async (): Promise<void> => {
        dashboardRequestCount += 1;
      });
      detailMerger.run(async (): Promise<void> => {
        detailRequestCount += 1;
      });
      expect(dashboardRequestCount).assertEqual(2);
      expect(detailRequestCount).assertEqual(1);
      releaseDetail();
      await detail;
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

    it('ordersVisibleGroupsByMode', 0, () => {
      const groups: ProxyGroupSnapshot[] = [
        { name: 'Second', type: 'Selector', selected: 'B', selectable: true, hidden: false, nodes: [] },
        { name: 'First', type: 'Selector', selected: 'A', selectable: true, hidden: false, nodes: [] },
        { name: 'GLOBAL', type: 'Selector', selected: 'A', selectable: true, hidden: false, nodes: [] },
        { name: 'Hidden', type: 'Selector', selected: 'A', selectable: true, hidden: true, nodes: [] }
      ];
      const ruleGroups = visibleProxyGroups(groups, RuntimeMode.RULE);
      expect(ruleGroups.length).assertEqual(2);
      expect(ruleGroups[0].name).assertEqual('Second');
      expect(ruleGroups[1].name).assertEqual('First');
      const globalGroups = visibleProxyGroups(groups, RuntimeMode.GLOBAL);
      expect(globalGroups.length).assertEqual(3);
      expect(globalGroups[0].name).assertEqual('GLOBAL');
      expect(resolveSelectedProxyGroup(groups, RuntimeMode.GLOBAL, 'First')).assertEqual('First');
      expect(resolveSelectedProxyGroup(groups, RuntimeMode.GLOBAL, 'Missing')).assertEqual('GLOBAL');
      expect(resolveSelectedProxyGroup(groups, RuntimeMode.DIRECT, 'GLOBAL')).assertEqual('Second');
    });

    it('givesLatestDelayOperationNodeOwnership', 0, () => {
      const registry = new ProxyDelayOperationRegistry();
      registry.start('group-operation', 'Auto', '', ['A', 'B']);
      registry.start('node-operation', 'Auto', 'B', ['B']);
      expect(registry.accept('group-operation', 'Auto', 'B')).assertFalse();
      expect(registry.accept('group-operation', 'Auto', 'A')).assertTrue();
      expect(registry.accept('node-operation', 'Auto', 'B')).assertTrue();
      expect(registry.complete('group-operation').length).assertEqual(0);
      expect(registry.complete('node-operation').length).assertEqual(0);
      expect(registry.snapshots().length).assertEqual(0);
    });
  });
}
