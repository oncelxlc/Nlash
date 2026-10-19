/** Core 的 host 不含端口，destination 使用 IP:port（IPv6 带方括号）。 */
export function requestEndpoint(host: string, destination: string): string {
  if (host.length === 0) { return destination; }
  const match = destination.match(/:(\d+)$/);
  if (match === null) { return host; }
  return `${host.includes(':') && !host.startsWith('[') ? `[${host}]` : host}:${match[1]}`;
}

export function sampledSpeed(total: number, previous: number | undefined, elapsedMs: number): number {
  return previous === undefined || elapsedMs <= 0 ? 0 : Math.max(0, total - previous) * 1000 / elapsedMs;
}

export function formatRecordTime(timestamp: number): string {
  if (!Number.isFinite(timestamp) || timestamp <= 0) { return '--'; }
  const date = new Date(timestamp);
  const pad = (value: number): string => value.toString().padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
    `${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

export function elapsedLabel(timestamp: number, now: number = Date.now()): string {
  if (!Number.isFinite(timestamp) || timestamp <= 0) { return '未下载'; }
  const seconds = Math.max(0, Math.floor((now - timestamp) / 1000));
  if (seconds < 60) { return '刚刚'; }
  if (seconds < 3600) { return `${Math.floor(seconds / 60)} 分钟前`; }
  if (seconds < 86400) { return `${Math.floor(seconds / 3600)} 小时前`; }
  return `${Math.floor(seconds / 86400)} 天前`;
}
