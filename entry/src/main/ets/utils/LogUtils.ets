import { LOG_LEVELS, LOG_LEVEL_LABELS } from '../constants/LogConstants';
import { LogRecord, LogSnapshot } from '../model/LogModels';

export function isValidLogSnapshot(snapshot: LogSnapshot): boolean {
  return snapshot !== null && typeof snapshot === 'object' && typeof snapshot.capture === 'boolean' &&
    LOG_LEVELS.includes(snapshot.level) && Array.isArray(snapshot.records) && snapshot.records.length <= 500 &&
    snapshot.records.every((record: LogRecord): boolean => record !== null && typeof record === 'object' &&
      typeof record.id === 'string' && record.id.length > 0 && Number.isFinite(record.time) && record.time > 0 &&
      LOG_LEVELS.includes(record.level) && typeof record.message === 'string' && record.message.length <= 2051);
}

export function formatLogTime(timestamp: number): string {
  const date = new Date(timestamp);
  const day = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  const time = `${String(date.getHours()).padStart(2, '0')}:${String(date.getMinutes()).padStart(2, '0')}:` +
    `${String(date.getSeconds()).padStart(2, '0')}.${String(date.getMilliseconds()).padStart(3, '0')}`;
  return `${day} ${time}`;
}

export function filterLogs(records: LogRecord[], query: string): LogRecord[] {
  const keyword = query.trim().toLowerCase();
  return records.filter((record: LogRecord): boolean =>
    `${formatLogTime(record.time)} ${record.level} ${LOG_LEVEL_LABELS[LOG_LEVELS.indexOf(record.level)]} ${record.message}`
      .toLowerCase().includes(keyword));
}

export function buildLogFileName(appName: string, timestamp: number): string {
  const name = appName.replace(/[\\/:*?"<>|\u0000-\u001f]/g, '_').trim() || 'Nlash';
  const date = formatLogTime(timestamp).slice(0, 19).replace(/:/g, '-').replace(' ', '_');
  return `${name}_${date}.log`;
}

export function formatLogExport(records: LogRecord[]): string {
  return records.slice().reverse().map((record: LogRecord): string =>
    `${formatLogTime(record.time)} [${record.level.toUpperCase()}] ${record.message}`).join('\n') + '\n';
}
