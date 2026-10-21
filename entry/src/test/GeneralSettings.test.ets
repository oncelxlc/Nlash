import { describe, expect, it } from '@ohos/hypium';
import { formatHostOverrides, parseHostOverrides, parseMixedPort } from '../main/ets/utils/GeneralSettingsUtils';
import { mergeProxyTrafficSnapshot } from '../main/ets/utils/RuntimeUtils';
import { DashboardSnapshot, RuntimeMode } from '../main/ets/model/RuntimeModels';
import { buildPlatformVpnConfig } from '../main/ets/utils/VpnUtils';
import { isValidDelayTestUrl } from '../main/ets/utils/SettingsUtils';

export default function generalSettingsTest() {
  describe('generalSettings', () => {
    it('validatesDelayTestUrlsBeforePersistingThem', 0, () => {
      expect(isValidDelayTestUrl('https://www.gstatic.com/generate_204')).assertTrue();
      expect(isValidDelayTestUrl('http://127.0.0.1:8080/test?q=1')).assertTrue();
      ['https://', 'file:///test', 'https://user:pass@example.com', 'https://test.com/has space', 'https://test.com/#fragment']
        .forEach((value: string): void => { expect(isValidDelayTestUrl(value)).assertFalse(); });
    });
    it('keepsPlatformAddressesAndDefaultRoutesInSyncWithIPv6', 0, () => {
      const ipv4 = buildPlatformVpnConfig(1400, false);
      expect(ipv4.addresses.length).assertEqual(1);
      expect(ipv4.routes?.length).assertEqual(1);
      expect(ipv4.isIPv6Accepted).assertFalse();
      const dualStack = buildPlatformVpnConfig(1500, true);
      expect(dualStack.mtu).assertEqual(1500);
      expect(dualStack.isIPv4Accepted).assertTrue();
      expect(dualStack.isIPv6Accepted).assertTrue();
      expect(dualStack.addresses[1].address.address).assertEqual('fdfe:dcba:9876::1');
      expect(dualStack.addresses[1].prefixLength).assertEqual(126);
      expect(dualStack.routes?.length).assertEqual(2);
      expect(dualStack.routes?.[1].destination.prefixLength).assertEqual(0);
    });
    it('validatesMixedPortWithoutCoercingEmptyOrFractionalInput', 0, () => {
      expect(parseMixedPort(' 7890 ')).assertEqual(7890);
      expect(parseMixedPort('0')).assertEqual(0);
      expect(parseMixedPort('65535')).assertEqual(65535);
      ['', ' ', '-1', '65536', '7890.5', '1e3', 'abc'].forEach((input: string): void => {
        let rejected = false;
        try { parseMixedPort(input); } catch (_error) { rejected = true; }
        expect(rejected).assertTrue();
      });
    });

    it('roundTripsHostsAndRejectsDuplicateOrIncompleteEntries', 0, () => {
      const text = 'example.com = 192.0.2.1, 2001:db8::1\nalias.example = example.com';
      const hosts = parseHostOverrides(text);
      expect(hosts.length).assertEqual(2);
      expect(hosts[0].value).assertEqual('192.0.2.1, 2001:db8::1');
      expect(formatHostOverrides(hosts)).assertEqual(text);
      expect(parseHostOverrides(' \n ').length).assertEqual(0);
      ['no-equals', ' = 1.1.1.1', 'test.com = ', 'test.com = 1.1.1.1\nTEST.COM = 2.2.2.2']
        .forEach((input: string): void => {
          let rejected = false;
          try { parseHostOverrides(input); } catch (_error) { rejected = true; }
          expect(rejected).assertTrue();
        });
    });

    it('startsANewTrafficBaselineWhenTheScopeChanges', 0, () => {
      const previous: DashboardSnapshot = {
        mode: RuntimeMode.RULE, uploadSpeed: 200, downloadSpeed: 300, uploadTotal: 400,
        downloadTotal: 500, memoryBytes: 1024, connectionCount: 1, onlyProxyTraffic: false
      };
      const proxy: DashboardSnapshot = {
        mode: RuntimeMode.RULE, uploadSpeed: 100, downloadSpeed: 200, uploadTotal: 100,
        downloadTotal: 200, memoryBytes: 1024, connectionCount: 1, onlyProxyTraffic: true
      };
      const changed = mergeProxyTrafficSnapshot(proxy, previous, previous);
      expect(changed.uploadTotal).assertEqual(0);
      expect(changed.downloadTotal).assertEqual(0);
      expect(changed.uploadSpeed).assertEqual(0);
      expect(changed.onlyProxyTraffic).assertTrue();
      const baseline: DashboardSnapshot = {
        mode: RuntimeMode.RULE, uploadSpeed: 0, downloadSpeed: 0, uploadTotal: 90,
        downloadTotal: 180, memoryBytes: 1024, connectionCount: 1, onlyProxyTraffic: true
      };
      const next = mergeProxyTrafficSnapshot(proxy, changed, baseline);
      expect(next.uploadTotal).assertEqual(10);
      expect(next.downloadTotal).assertEqual(20);
    });
  });
}
