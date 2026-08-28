export enum FeedbackLevel {
  INFO = 'INFO',
  SUCCESS = 'SUCCESS',
  WARNING = 'WARNING',
  ERROR = 'ERROR'
}

export interface FeedbackEvent {
  id: number;
  level: FeedbackLevel;
  message: string;
}

export type FeedbackListener = (event: FeedbackEvent) => void;

