import { ArgumentMatchers, describe, expect, it, MockKit, when } from '@ohos/hypium';
import { ConnectionSnapshot, ConnectionsSnapshot, DashboardSnapshot, ProxySnapshot, RuntimeCommandResponse,
  RuntimeMode, ProxySnapshotSource } from '../main/ets/model/RuntimeModels';
import { CoreServiceState, ProxyState, RuntimeLifecycleListener } from '../main/ets/model/VpnModels';
import { runtimeControlService } from '../main/ets/services/RuntimeControlService';
import { vpnService } from '../main/ets/services/VpnService';
import { profileStore } from '../main/ets/stores/ProfileStore';
import { runtimeStore } from '../main/ets/stores/RuntimeStore';

export default function runtimeSessionTest() {
  describe('runtimeSession', () => {
    it('clearsOnDisableAndRejectsResponsesFromThePreviousSession', 0, async () => {
      const mocker = new MockKit();
      let lifecycle: RuntimeLifecycleListener = (): void => {};
      when(mocker.mockFunc(vpnService, vpnService.subscribeLifecycle))(ArgumentMatchers.anyFunction)
        .afterAction((listener: RuntimeLifecycleListener): (() => void) => {
          lifecycle = listener;
          return (): void => {};
        });
      when(mocker.mockFunc(profileStore, profileStore.subscribe))(ArgumentMatchers.anyFunction)
        .afterReturn((): void => {});
      when(mocker.mockFunc(runtimeControlService, runtimeControlService.initialize))().afterReturn(Promise.resolve());
      const execute = mocker.mockFunc(runtimeControlService, runtimeControlService.execute);
      const ok: RuntimeCommandResponse<Object> = { ok: true, code: 'OK', message: '' };
      when(execute)('applyProxySelections').afterReturn(Promise.resolve(ok));
      when(execute)('closeAllConnections').afterReturn(Promise.resolve(ok));
      const proxies: ProxySnapshot = { source: ProxySnapshotSource.RUNTIME, mode: RuntimeMode.RULE, groups: [] };
      const proxyResponse: RuntimeCommandResponse<ProxySnapshot> = { ok: true, code: 'OK', message: '', data: proxies };
      when(execute)('proxySnapshot').afterReturn(Promise.resolve(proxyResponse));
      const connection: ConnectionSnapshot = { id: 'session-1', network: 'tcp', type: 'TUN',
        host: 'example.test', destination: '192.0.2.1:443', source: '', process: '', start: 1, upload: 4, download: 8,
        chains: [], rule: '', rulePayload: '' };
      const connections: ConnectionsSnapshot = { connections: [connection], uploadTotal: 4, downloadTotal: 8,
        memoryBytes: 0 };
      const connectionResponse: RuntimeCommandResponse<ConnectionsSnapshot> = {
        ok: true, code: 'OK', message: '', data: connections
      };
      let connectionReads = 0;
      let pendingConnection: Promise<RuntimeCommandResponse<ConnectionsSnapshot>> = Promise.resolve(connectionResponse);
      when(execute)('connectionSnapshot').afterAction((): Promise<RuntimeCommandResponse<ConnectionsSnapshot>> => {
        connectionReads++;
        return pendingConnection;
      });
      const dashboard: DashboardSnapshot = { mode: RuntimeMode.RULE, uploadSpeed: 4, downloadSpeed: 8,
        uploadTotal: 4, downloadTotal: 8, memoryBytes: 0, connectionCount: 1 };
      const dashboardResponse: RuntimeCommandResponse<DashboardSnapshot> = {
        ok: true, code: 'OK', message: '', data: dashboard
      };
      let pendingDashboard: Promise<RuntimeCommandResponse<DashboardSnapshot>> = Promise.resolve(dashboardResponse);
      when(execute)('dashboardSnapshot').afterAction((): Promise<RuntimeCommandResponse<DashboardSnapshot>> =>
        pendingDashboard);
      const emit = (state: ProxyState, core: CoreServiceState = CoreServiceState.RUNNING): void => {
        lifecycle({ coreState: core, proxyState: state, profileId: '', profileSignature: '', message: '',
          sessionStartedAt: 0, sessionEndedAt: 0 });
      };
      runtimeStore.setForeground(false);
      try {
        runtimeStore.initialize();
        emit(ProxyState.ENABLED);
        await runtimeStore.closeAllConnections();
        await runtimeStore.refresh();
        expect(runtimeStore.getSnapshot().requests.length).assertEqual(1);
        expect(runtimeStore.getSnapshot().trafficHistory.length).assertEqual(1);
        emit(ProxyState.DISABLING);
        let snapshot = runtimeStore.getSnapshot();
        expect(snapshot.proxyEnabled).assertFalse();
        expect(snapshot.requests.length).assertEqual(0);
        expect(snapshot.connections.length).assertEqual(0);
        expect(snapshot.trafficHistory.length).assertEqual(0);
        expect(snapshot.dashboard).assertUndefined();
        const readsBefore = connectionReads;
        await runtimeStore.closeAllConnections();
        expect(connectionReads).assertEqual(readsBefore);

        emit(ProxyState.ENABLED);
        let releaseConnection: (value: RuntimeCommandResponse<ConnectionsSnapshot>) => void = (): void => {};
        pendingConnection = new Promise<RuntimeCommandResponse<ConnectionsSnapshot>>((resolve): void => {
          releaseConnection = resolve;
        });
        const oldConnection = runtimeStore.closeAllConnections();
        await Promise.resolve();
        await Promise.resolve();
        emit(ProxyState.DISABLED);
        emit(ProxyState.ENABLED);
        releaseConnection(connectionResponse);
        await oldConnection;
        expect(runtimeStore.getSnapshot().requests.length).assertEqual(0);

        let releaseDashboard: (value: RuntimeCommandResponse<DashboardSnapshot>) => void = (): void => {};
        pendingDashboard = new Promise<RuntimeCommandResponse<DashboardSnapshot>>((resolve): void => {
          releaseDashboard = resolve;
        });
        const oldDashboard = runtimeStore.refresh();
        emit(ProxyState.DISABLED);
        emit(ProxyState.ENABLED);
        releaseDashboard(dashboardResponse);
        await oldDashboard;
        snapshot = runtimeStore.getSnapshot();
        expect(snapshot.dashboard).assertUndefined();
        expect(snapshot.trafficHistory.length).assertEqual(0);

        await runtimeStore.closeAllConnections();
        expect(runtimeStore.getSnapshot().requests.length).assertEqual(1);
        emit(ProxyState.ENABLED, CoreServiceState.ERROR);
        expect(runtimeStore.getSnapshot().requests.length).assertEqual(0);
        expect(runtimeStore.getSnapshot().connections.length).assertEqual(0);
      } finally {
        emit(ProxyState.DISABLED, CoreServiceState.STOPPED);
        mocker.clear(vpnService);
        mocker.clear(profileStore);
        mocker.clear(runtimeControlService);
      }
    });
  });
}
