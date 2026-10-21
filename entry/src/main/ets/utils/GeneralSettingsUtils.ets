import { HostOverride } from '../model/GeneralSettingsModels';

export function parseMixedPort(input: string): number {
  const text = input.trim();
  const port = Number(text);
  if (!/^\d+$/.test(text) || !Number.isInteger(port) || port < 0 || port > 65535) {
    throw new Error('端口须为 0–65535 的整数，0 表示关闭');
  }
  return port;
}

export function parseHostOverrides(input: string): HostOverride[] {
  const entries: HostOverride[] = [];
  const seen = new Set<string>();
  input.split('\n').forEach((line: string): void => {
    const text = line.trim();
    if (text.length === 0) { return; }
    const separator = text.indexOf('=');
    const host = text.substring(0, separator).trim().toLowerCase();
    const value = text.substring(separator + 1).trim();
    if (separator <= 0 || host.length > 253 || /[\s/:=\u0000]/.test(host) || value.length === 0 || value.length > 1024) {
      throw new Error('每行填写“域名 = IP 或域名”，多个 IP 用逗号分隔');
    }
    if (seen.has(host)) { throw new Error(`Hosts 域名重复：${host}`); }
    seen.add(host);
    entries.push({ host: host, value: value });
  });
  if (entries.length > 64) { throw new Error('Hosts 最多支持 64 条'); }
  return entries;
}

export function formatHostOverrides(entries: HostOverride[]): string {
  return entries.map((entry: HostOverride): string => `${entry.host} = ${entry.value}`).join('\n');
}
