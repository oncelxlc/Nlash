import { describe, expect, it } from '@ohos/hypium';
import { IpNetworkType, IpQuality } from '../main/ets/model/RuntimeModels';
import { isValidIpv4, parseGeoIpResponse, parseIpQueryResponse, resolvePublicNetwork } from '../main/ets/services/LocalNetworkService';

function ipInfo(score: number, hosting: boolean = false, vpn: boolean = false,
  proxy: boolean = false, tor: boolean = false): string {
  return `{"ip":"8.8.8.8","isp":{"org":"Example Network"},` +
    `"location":{"country":"Singapore","country_code":"sg"},` +
    `"risk":{"risk_score":${score},"is_datacenter":${hosting},"is_mobile":false,` +
    `"is_vpn":${vpn},"is_proxy":${proxy},"is_tor":${tor}}}`;
}

export default function publicNetworkTest() {
  describe('publicNetwork', () => {
    it('acceptsOnlyDottedDecimalIpv4', 0, () => {
      ['1e2.1.1.1', '0xff.1.1.1', '+1.2.3.4', '1. 2.3.4', '01.2.3.4', '256.2.3.4', ''].forEach((ip: string): void => {
        expect(isValidIpv4(ip)).assertFalse();
      });
      expect(isValidIpv4(' 8.8.8.8\n')).assertTrue();
    });

    it('gradesRiskAndHostingFromRealProviderFields', 0, () => {
      const info = parseIpQueryResponse(ipInfo(20, true), '8.8.8.8');
      expect(info.organization).assertEqual('Example Network');
      expect(info.countryCode).assertEqual('SG');
      expect(info.networkType).assertEqual(IpNetworkType.HOSTING);
      expect(info.riskScore).assertEqual(20);
      expect(info.quality).assertEqual(IpQuality.NORMAL);
      expect(parseIpQueryResponse(ipInfo(0), '8.8.8.8').quality).assertEqual(IpQuality.GOOD);
      expect(parseIpQueryResponse(ipInfo(19), '8.8.8.8').quality).assertEqual(IpQuality.GOOD);
      expect(parseIpQueryResponse(ipInfo(59), '8.8.8.8').quality).assertEqual(IpQuality.NORMAL);
      expect(parseIpQueryResponse(ipInfo(60), '8.8.8.8').quality).assertEqual(IpQuality.POOR);
      expect(parseIpQueryResponse(ipInfo(100), '8.8.8.8').quality).assertEqual(IpQuality.POOR);
      expect(parseIpQueryResponse(ipInfo(0, true), '8.8.8.8').quality).assertEqual(IpQuality.NORMAL);
      expect(parseIpQueryResponse(ipInfo(0, false, true), '8.8.8.8').quality).assertEqual(IpQuality.NORMAL);
      expect(parseIpQueryResponse(ipInfo(0, false, false, true), '8.8.8.8').quality).assertEqual(IpQuality.POOR);
      expect(parseIpQueryResponse(ipInfo(0, false, false, false, true), '8.8.8.8').quality).assertEqual(IpQuality.POOR);
      expect(parseIpQueryResponse(ipInfo(0), '8.8.8.8').networkType).assertEqual(IpNetworkType.NON_HOSTING);
      expect(parseIpQueryResponse(ipInfo(0).replace('"is_mobile":false', '"is_mobile":true'), '8.8.8.8').networkType)
        .assertEqual(IpNetworkType.MOBILE);
    });

    it('neverTreatsMissingOrMalformedRiskAsGood', 0, () => {
      [ipInfo(-1), ipInfo(101), ipInfo(0.5), ipInfo(0).replace('"is_vpn":false,', ''),
        ipInfo(0).replace('"is_proxy":false', '"is_proxy":"false"'),
        '{"ip":"8.8.8.8"}', '{"ip":"8.8.8.8","risk":null}'].forEach((raw: string): void => {
        const info = parseIpQueryResponse(raw, '8.8.8.8');
        expect(info.quality).assertEqual(IpQuality.UNKNOWN);
        expect((info.qualityError ?? '').length > 0).assertTrue();
      });
    });

    it('rejectsMixedAddressAndInvalidPayloads', 0, () => {
      ['null', '[]', '{', '{}', ipInfo(0).replace('8.8.8.8', '1.1.1.1')].forEach((raw: string): void => {
        let failed = false;
        try { parseIpQueryResponse(raw, '8.8.8.8'); } catch (_error) { failed = true; }
        expect(failed).assertTrue();
      });
      let failed = false;
      try { parseGeoIpResponse('{"country_code":"US"}', '8.8.8.8'); } catch (_error) { failed = true; }
      expect(failed).assertTrue();
    });

    it('usesOrganizationFallbackAndValidCountryCodes', 0, () => {
      const info = parseGeoIpResponse(
        '{"ip":"8.8.8.8","organization":"","asn_organization":"Example ASN","country_code":"bad"}', '8.8.8.8');
      expect(info.organization).assertEqual('Example ASN');
      expect(info.countryCode).assertEqual('');
      expect(parseIpQueryResponse('{"ip":"8.8.8.8","isp":{"isp":"Example ISP"}}', '8.8.8.8').organization)
        .assertEqual('Example ISP');
    });

    it('looksUpTheDetectedAddressAndFallsBackForIpv4Only', 0, async () => {
      const calls: string[] = [];
      const info = await resolvePublicNetwork(async (url: string, _accept: string): Promise<string> => {
        calls.push(url);
        if (url === 'https://api.ipify.org') { throw new Error('unavailable'); }
        if (url === 'https://api-ipv4.ip.sb/ip') { return '8.8.8.8\n'; }
        expect(url).assertEqual('https://api.ipquery.io/8.8.8.8');
        return ipInfo(20, true);
      });
      expect(calls.length).assertEqual(3);
      expect(info.quality).assertEqual(IpQuality.NORMAL);
      expect(info.publicIpv4).assertEqual('8.8.8.8');
    });

    it('preservesFreshIpAndGeoWhenQualityLookupFails', 0, async () => {
      const info = await resolvePublicNetwork(async (url: string, _accept: string): Promise<string> => {
        if (url === 'https://api.ipify.org') { return '8.8.8.8'; }
        if (url === 'https://api.ipquery.io/8.8.8.8') { throw new Error('HTTP 429'); }
        expect(url).assertEqual('https://api.ip.sb/geoip/8.8.8.8');
        return '{"ip":"8.8.8.8","country_code":"US","organization":"Example ASN"}';
      });
      expect(info.publicIpv4).assertEqual('8.8.8.8');
      expect(info.countryCode).assertEqual('US');
      expect(info.organization).assertEqual('Example ASN');
      expect(info.quality).assertEqual(IpQuality.UNKNOWN);
      expect(info.riskScore).assertUndefined();
      expect((info.qualityError ?? '').length > 0).assertTrue();
    });

    it('doesNotDropKnownIpWhenBothInformationServicesFail', 0, async () => {
      const info = await resolvePublicNetwork(async (url: string, _accept: string): Promise<string> => {
        if (url === 'https://api.ipify.org') { return '8.8.8.8'; }
        throw new Error('offline');
      });
      expect(info.publicIpv4).assertEqual('8.8.8.8');
      expect(info.quality).assertEqual(IpQuality.UNKNOWN);
      expect(info.countryCode).assertEqual('');
      expect(info.errorMessage.length > 0).assertTrue();
    });
  });
}
