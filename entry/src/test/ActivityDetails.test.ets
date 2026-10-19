import { describe, expect, it } from '@ohos/hypium';
import { elapsedLabel, formatRecordTime, requestEndpoint, sampledSpeed } from '../main/ets/utils/ActivityUtils';
import { dnsInitiatorLabel, filterDnsQueries, resourceInputError } from '../main/ets/utils/DiagnosticsUtils';
import { DnsQueryRecord } from '../main/ets/model/DiagnosticsModels';

export default function activityDetailsTest() {
  describe('activityDetails', () => {
    it('preservesDestinationPortsAndIpv6', 0, () => {
      expect(requestEndpoint('example.com', '1.1.1.1:443')).assertEqual('example.com:443');
      expect(requestEndpoint('', '[2001:db8::1]:53')).assertEqual('[2001:db8::1]:53');
      expect(requestEndpoint('2001:db8::1', '[2001:db8::1]:443')).assertEqual('[2001:db8::1]:443');
      expect(requestEndpoint('example.com', '')).assertEqual('example.com');
    });
    it('samplesRatesWithoutInventingFirstSampleTraffic', 0, () => {
      expect(sampledSpeed(4096, undefined, 2000)).assertEqual(0);
      expect(sampledSpeed(4096, 2048, 2000)).assertEqual(1024);
      expect(sampledSpeed(0, 2048, 2000)).assertEqual(0);
      expect(sampledSpeed(4096, 2048, 0)).assertEqual(0);
    });
    it('formatsMissingAndFutureTimestamps', 0, () => {
      expect(elapsedLabel(0)).assertEqual('未下载');
      expect(elapsedLabel(2000, 1000)).assertEqual('刚刚');
      expect(elapsedLabel(1000, 3601000)).assertEqual('1 小时前');
      expect(formatRecordTime(0)).assertEqual('--');
    });
    it('searchesDnsAnswersAndUpstreamsCaseInsensitively', 0, () => {
      const records: DnsQueryRecord[] = [{ id: '1', host: 'example.com', type: 'AAAA',
        answers: ['2001:db8::1'], initiator: 'direct', upstream: 'https://dns.example/dns-query',
        cached: true, start: 1000, duration: 0, error: '' }];
      expect(filterDnsQueries(records, ' AAAA ').length).assertEqual(1);
      expect(filterDnsQueries(records, '2001:DB8').length).assertEqual(1);
      expect(filterDnsQueries(records, 'dns.example').length).assertEqual(1);
      expect(filterDnsQueries(records, '直连').length).assertEqual(1);
      expect(filterDnsQueries(records, 'missing').length).assertEqual(0);
      expect(dnsInitiatorLabel('rule')).assertEqual('规则');
    });
    it('validatesDownloadSourcesAndWholeHourIntervals', 0, () => {
      expect(resourceInputError('https://example.com/geoip.dat', false)).assertEqual('');
      expect(resourceInputError('file:///tmp/data', false).length > 0).assertTrue();
      expect(resourceInputError('https://user:pass@example.com/data', false).length > 0).assertTrue();
      expect(resourceInputError('https://example.com/#fragment', false).length > 0).assertTrue();
      expect(resourceInputError('24', true)).assertEqual('');
      expect(resourceInputError('', true).length > 0).assertTrue();
      expect(resourceInputError('0', true).length > 0).assertTrue();
      expect(resourceInputError('1.5', true).length > 0).assertTrue();
      expect(resourceInputError('721', true).length > 0).assertTrue();
    });
  });
}
