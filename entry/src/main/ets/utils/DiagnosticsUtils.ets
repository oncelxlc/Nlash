import { DnsQueryRecord } from '../model/DiagnosticsModels';

export function dnsInitiatorLabel(initiator: string): string {
  switch (initiator) {
    case 'app': return '应用';
    case 'rule': return '规则';
    case 'direct': return '直连';
    case 'proxy': return '代理';
    default: return '其他';
  }
}

export function filterDnsQueries(records: DnsQueryRecord[], query: string): DnsQueryRecord[] {
  const keyword = query.trim().toLowerCase();
  return records.filter((record: DnsQueryRecord): boolean =>
    [record.host, record.type, record.answers.join(' '), record.upstream, dnsInitiatorLabel(record.initiator)]
      .join(' ').toLowerCase().includes(keyword));
}

export function resourceInputError(value: string, interval: boolean): string {
  const text = value.trim();
  if (interval) {
    return /^\d+$/.test(text) && Number(text) >= 1 && Number(text) <= 720 ? '' : '请输入 1–720 之间的整数小时';
  }
  return text.length <= 2048 && /^https?:\/\/[^/\s?#@]+(?:[/?][^\s#]*)?$/.test(text) ? '' :
    '请输入有效的 HTTP(S) 下载地址，不含账号或片段';
}
