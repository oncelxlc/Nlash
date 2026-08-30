import { describe, expect, it } from '@ohos/hypium';
import {
  CoreServiceState,
  CoreRestartAction,
  decodeVpnStateEnvelope,
  encodeVpnStateEnvelope,
  formatVpnRunDuration,
  resolveVpnConnectedAt,
  resolveProxyConnectedAt,
  resolveCoreRestartAction,
  VpnState,
  ProxyState,
  vpnStateFromProxyState,
  VpnStateEnvelope,
  VpnStateSequenceTracker
} from '../main/ets/models/VpnModels';

export default function vpnModelsTest() {
  describe('vpnModels', () => {
    it('roundTripsCrossProcessStateEvent', 0, () => {
      const input: VpnStateEnvelope = {
        sourceId: 'source-a',
        sourceStartedAt: 100,
        sequence: 1,
        event: {
          state: VpnState.CONNECTED,
          coreState: CoreServiceState.RUNNING,
          proxyState: ProxyState.ENABLED,
          profileId: 'profile-a',
          profileSignature: 'profile-a:path:1',
          message: 'Mihomo and TUN connected'
        }
      };
      const output = decodeVpnStateEnvelope(encodeVpnStateEnvelope(input));

      expect(output !== undefined).assertTrue();
      expect(output?.event.state).assertEqual(VpnState.CONNECTED);
      expect(output?.event.coreState).assertEqual(CoreServiceState.RUNNING);
      expect(output?.event.proxyState).assertEqual(ProxyState.ENABLED);
      expect(output?.event.message).assertEqual(input.event.message);
    });

    it('rejectsMalformedOrUnknownStateEvent', 0, () => {
      expect(decodeVpnStateEnvelope('{')).assertUndefined();
      expect(decodeVpnStateEnvelope('{"sourceId":"a","sourceStartedAt":1,"sequence":1,' +
        '"event":{"state":"UNKNOWN","coreState":"RUNNING","proxyState":"DISABLED",' +
        '"profileId":"","profileSignature":"","message":"ignored"}}')).assertUndefined();
      expect(decodeVpnStateEnvelope('{"sourceId":"a","sourceStartedAt":1,"sequence":0,' +
        '"event":{"state":"ERROR","coreState":"ERROR","proxyState":"ERROR",' +
        '"profileId":"","profileSignature":"","message":"ignored"}}')).assertUndefined();
    });

    it('rejectsLateAndPreviousProcessStateEvents', 0, () => {
      const tracker = new VpnStateSequenceTracker();
      const first: VpnStateEnvelope = {
        sourceId: 'source-a',
        sourceStartedAt: 100,
        sequence: 1,
        event: {
          state: VpnState.STARTING, coreState: CoreServiceState.RUNNING, proxyState: ProxyState.ENABLING,
          profileId: 'profile-a', profileSignature: 'profile-a:path:1', message: 'starting'
        }
      };
      const second: VpnStateEnvelope = {
        sourceId: 'source-a',
        sourceStartedAt: 100,
        sequence: 2,
        event: {
          state: VpnState.ERROR, coreState: CoreServiceState.RUNNING, proxyState: ProxyState.ERROR,
          profileId: 'profile-a', profileSignature: 'profile-a:path:1', message: 'failed'
        }
      };
      const newerProcess: VpnStateEnvelope = {
        sourceId: 'source-b',
        sourceStartedAt: 200,
        sequence: 1,
        event: {
          state: VpnState.STARTING, coreState: CoreServiceState.RELOADING,
          proxyState: ProxyState.DISABLED, profileId: 'profile-a',
          profileSignature: 'profile-a:path:2', message: 'restarted'
        }
      };

      expect(tracker.accept(first)).assertTrue();
      expect(tracker.accept(second)).assertTrue();
      expect(tracker.accept(first)).assertFalse();
      expect(tracker.accept(newerProcess)).assertTrue();
      expect(tracker.accept(second)).assertFalse();
    });

    it('resolvesCoreRestartActions', 0, () => {
      expect(resolveCoreRestartAction(VpnState.IDLE)).assertEqual(CoreRestartAction.START);
      expect(resolveCoreRestartAction(VpnState.DISCONNECTED)).assertEqual(CoreRestartAction.START);
      expect(resolveCoreRestartAction(VpnState.CONNECTED)).assertEqual(CoreRestartAction.RESTART);
      expect(resolveCoreRestartAction(VpnState.ERROR)).assertEqual(CoreRestartAction.RESTART);
      expect(resolveCoreRestartAction(VpnState.STARTING)).assertEqual(CoreRestartAction.BLOCKED);
      expect(resolveCoreRestartAction(VpnState.STOPPING)).assertEqual(CoreRestartAction.BLOCKED);
    });

    it('formatsSingleRunDuration', 0, () => {
      expect(formatVpnRunDuration(0)).assertEqual('00:00:00');
      expect(formatVpnRunDuration(65)).assertEqual('00:01:05');
      expect(formatVpnRunDuration(3661)).assertEqual('01:01:01');
      expect(formatVpnRunDuration(360061)).assertEqual('100:01:01');
      expect(formatVpnRunDuration(-1)).assertEqual('00:00:00');
    });

    it('tracksSingleRunStartAcrossVpnStates', 0, () => {
      const startedAt = resolveVpnConnectedAt(VpnState.STARTING, VpnState.CONNECTED, 0, 1000);
      expect(startedAt).assertEqual(1000);
      expect(resolveVpnConnectedAt(VpnState.CONNECTED, VpnState.CONNECTED, startedAt, 2000))
        .assertEqual(startedAt);
      expect(resolveVpnConnectedAt(VpnState.CONNECTED, VpnState.STOPPING, startedAt, 3000))
        .assertEqual(startedAt);
      expect(resolveVpnConnectedAt(VpnState.STOPPING, VpnState.DISCONNECTED, startedAt, 4000))
        .assertEqual(0);
    });

    it('tracksProxyRunIndependentlyFromCoreState', 0, () => {
      const startedAt = resolveProxyConnectedAt(ProxyState.ENABLING, ProxyState.ENABLED, 0, 1000);
      expect(startedAt).assertEqual(1000);
      expect(resolveProxyConnectedAt(ProxyState.ENABLED, ProxyState.DISABLING, startedAt, 2000))
        .assertEqual(startedAt);
      expect(resolveProxyConnectedAt(ProxyState.DISABLING, ProxyState.ENABLED, startedAt, 2500))
        .assertEqual(startedAt);
      expect(resolveProxyConnectedAt(ProxyState.DISABLING, ProxyState.DISABLED, startedAt, 3000))
        .assertEqual(0);
      expect(vpnStateFromProxyState(ProxyState.DISABLED)).assertEqual(VpnState.DISCONNECTED);
    });
  });
}
