import { describe, expect, it } from '@ohos/hypium';
import {
  appendTrafficSample,
  buildTrafficChartPoints,
  buildTrafficDonutPath,
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

    it('drawsTrafficDonutWithProportionalSegmentsAndScalableCoordinates', 0, () => {
      const upload = buildTrafficDonutPath(1, 3, true, 96).split(' ').filter((part: string): boolean =>
        part !== 'M' && part !== 'A').map((part: string): number => Number(part));
      const download = buildTrafficDonutPath(1, 3, false, 96).split(' ').filter((part: string): boolean =>
        part !== 'M' && part !== 'A').map((part: string): number => Number(part));
      const uploadEnd = Math.atan2(upload[15] - 48, upload[14] - 48);
      const uploadStart = Math.atan2(upload[1] - 48, upload[0] - 48);
      const downloadStart = Math.atan2(download[1] - 48, download[0] - 48);
      expect(Math.abs(uploadEnd - uploadStart - Math.PI * 9 / 20) < 0.00001).assertTrue();
      expect(Math.abs(downloadStart - uploadEnd - Math.PI / 10) < 0.00001).assertTrue();
      expect(download[14] < 48).assertTrue();
      const scaled = buildTrafficDonutPath(1, 3, true, 192);
      expect(scaled.startsWith(`M ${upload[0] * 2} ${upload[1] * 2} A 84 84`)).assertTrue();
      expect(buildTrafficDonutPath(100, 300, true, 96)).assertEqual(buildTrafficDonutPath(1, 3, true, 96));
      expect(buildTrafficDonutPath(Number.MAX_VALUE, Number.MAX_VALUE, true, 96))
        .assertEqual(buildTrafficDonutPath(1, 1, true, 96));
    });

    it('handlesEmptyInvalidAndSingleDirectionTrafficDonuts', 0, () => {
      expect(buildTrafficDonutPath(0, 0, true, 96)).assertEqual('');
      expect(buildTrafficDonutPath(Number.NaN, -1, false, 96)).assertEqual('');
      expect(buildTrafficDonutPath(1, 1, true, 0)).assertEqual('');
      expect(buildTrafficDonutPath(1, 1, true, Number.POSITIVE_INFINITY)).assertEqual('');
      expect(buildTrafficDonutPath(0, 1, true, 96)).assertEqual('');
      expect(buildTrafficDonutPath(1, 0, false, 96)).assertEqual('');
      const fullCircle = buildTrafficDonutPath(1, 0, true, 96);
      expect(fullCircle.startsWith('M 48 6 A 42 42 0 0 1 48 90 A 42 42')).assertTrue();
      expect(buildTrafficDonutPath(0, 1, false, 96)).assertEqual(fullCircle);
      expect(buildTrafficDonutPath(Number.POSITIVE_INFINITY, 1, false, 96)).assertEqual(fullCircle);
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

    it('plotsCombinedSpeedWithinTheSixtySecondWindow', 0, () => {
      const history: TrafficSample[] = [
        { timestamp: 0, uploadSpeed: 40, downloadSpeed: 60 },
        { timestamp: 30000, uploadSpeed: 80, downloadSpeed: 120 },
        { timestamp: 60000, uploadSpeed: 60, downloadSpeed: 40 }
      ];
      const points = buildTrafficChartPoints(history, 300, 120);
      expect(points.length).assertEqual(3);
      expect(points[0].x).assertEqual(0);
      expect(points[1].x).assertEqual(150);
      expect(points[2].x).assertEqual(300);
      expect(points[0].y).assertEqual(66);
      expect(points[1].y).assertEqual(12);
      expect(points[2].y).assertEqual(66);
      expect(history[1].uploadSpeed).assertEqual(80);
    });

    it('handlesEmptyIdleAndSingleSampleCharts', 0, () => {
      const idle: TrafficSample[] = [{ timestamp: 1000, uploadSpeed: 0, downloadSpeed: 0 }];
      expect(buildTrafficChartPoints([], 300, 120).length).assertEqual(0);
      expect(buildTrafficChartPoints(idle, 0, 120).length).assertEqual(0);
      expect(buildTrafficChartPoints(idle, 300, Number.NaN).length).assertEqual(0);
      const idlePoints = buildTrafficChartPoints(idle, 300, 120);
      expect(idlePoints[0].x).assertEqual(300);
      expect(idlePoints[0].y).assertEqual(120);
      expect(idlePoints[0].slope).assertEqual(0);
      const activePoints = buildTrafficChartPoints([
        { timestamp: 1000, uploadSpeed: 160, downloadSpeed: 140 }
      ], 300, 120);
      expect(activePoints[0].x).assertEqual(300);
      expect(activePoints[0].y).assertEqual(12);
      expect(activePoints[0].slope).assertEqual(0);
    });

    it('keepsSmoothCurveHandlesWithinRealSampleRanges', 0, () => {
      const history: TrafficSample[] = [0, 40, 100, 60, 0].map((value: number, index: number): TrafficSample => ({
        timestamp: index * 15000, uploadSpeed: value, downloadSpeed: 0
      }));
      const points = buildTrafficChartPoints(history, 300, 112);
      expect(points[1].slope < 0).assertTrue();
      expect(points[2].slope).assertEqual(0);
      expect(points[3].slope > 0).assertTrue();
      for (let index = 1; index < points.length; index++) {
        const previous = points[index - 1];
        const current = points[index];
        const handleWidth = (current.x - previous.x) / 3;
        const firstY = previous.y + previous.slope * handleWidth;
        const lastY = current.y - current.slope * handleWidth;
        const minimum = Math.min(previous.y, current.y);
        const maximum = Math.max(previous.y, current.y);
        expect(firstY >= minimum && firstY <= maximum).assertTrue();
        expect(lastY >= minimum && lastY <= maximum).assertTrue();
      }
    });

    it('countsOnlyConnectedProxyIntervalsAndPreservesTrafficDuringRecovery', 0, () => {
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

    it('clearsCompletedSessionTrafficAndStartsTheNextSessionFromZero', 0, () => {
      const raw: DashboardSnapshot = {
        mode: RuntimeMode.GLOBAL, uploadSpeed: 30, downloadSpeed: 60,
        uploadTotal: 1000, downloadTotal: 2000, memoryBytes: 2048, connectionCount: 0
      };
      const stopped = mergeProxyTrafficSnapshot(raw, undefined, undefined);
      expect(stopped.uploadSpeed).assertEqual(0);
      expect(stopped.downloadSpeed).assertEqual(0);
      expect(stopped.uploadTotal).assertEqual(0);
      expect(stopped.downloadTotal).assertEqual(0);
      expect(stopped.mode).assertEqual(RuntimeMode.GLOBAL);
      expect(stopped.memoryBytes).assertEqual(2048);
      const restarted = mergeProxyTrafficSnapshot(raw, stopped, undefined);
      const next: DashboardSnapshot = {
        mode: RuntimeMode.GLOBAL, uploadSpeed: 10, downloadSpeed: 20,
        uploadTotal: 1010, downloadTotal: 2020, memoryBytes: 2048, connectionCount: 1
      };
      const active = mergeProxyTrafficSnapshot(next, restarted, raw);
      expect(active.uploadTotal).assertEqual(10);
      expect(active.downloadTotal).assertEqual(20);
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
      expect(proxyNodeRenderKey(partial[0].nodes[1])).assertEqual(proxyNodeRenderKey(reset[0].nodes[1]));
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
      expect(preserved === failed).assertTrue();
      expect(mergeGroupDelay(failed, 'Auto', [{ proxy: 'B', delay: 88, alive: true }]) === failed).assertTrue();
    });

    it('reusesUnchangedNodesWhenRefreshingProxyGroups', 0, () => {
      const current: ProxyGroupSnapshot[] = [{
        name: 'Route', type: 'Selector', selected: 'A', selectable: true, hidden: false,
        nodes: [
          { name: 'A', type: 'Vless', alive: false, tested: false, delay: 0, udp: true },
          { name: 'B', type: 'Vless', alive: false, tested: false, delay: 0, udp: false }
        ]
      }];
      const fresh: ProxyGroupSnapshot[] = [{
        name: 'Route', type: 'Selector', selected: 'B', selectable: true, hidden: false,
        nodes: [
          { name: 'A', type: 'Vless', alive: false, tested: false, delay: 0, udp: true },
          { name: 'B', type: 'Vless', alive: true, tested: true, delay: 64, udp: false }
        ]
      }];
      const refreshed = preserveTestedProxyDelays(fresh, current);
      expect(refreshed[0].selected).assertEqual('B');
      expect(refreshed[0].nodes[0] === current[0].nodes[0]).assertTrue();
      expect(refreshed[0].nodes[1].delay).assertEqual(64);
      expect(refreshed[0].nodes[1] === current[0].nodes[1]).assertFalse();
      expect(preserveTestedProxyDelays(fresh, refreshed) === refreshed).assertTrue();
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
