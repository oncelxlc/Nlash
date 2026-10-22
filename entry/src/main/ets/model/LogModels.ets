export enum LogLevel {
  DEBUG = 'debug',
  INFO = 'info',
  WARNING = 'warning',
  ERROR = 'error',
  SILENT = 'silent'
}

export interface LogRecord {
  id: string;
  time: number;
  level: LogLevel;
  message: string;
}

export interface LogSnapshot {
  capture: boolean;
  level: LogLevel;
  records: LogRecord[];
}
