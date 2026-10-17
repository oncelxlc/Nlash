/** 将 Unix 毫秒转换为本地时间，未提供有效正值时显示占位符。 */
export function formatLocalTime(timestamp: number): string {
  return timestamp > 0 ? new Date(timestamp).toLocaleTimeString() : '--';
}
