export function formatLocalTime(timestamp: number): string {
  return timestamp > 0 ? new Date(timestamp).toLocaleTimeString() : '--';
}
