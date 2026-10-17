export enum FeedbackLevel {
  INFO = 'INFO',
  SUCCESS = 'SUCCESS',
  WARNING = 'WARNING',
  ERROR = 'ERROR'
}

/** 每次发布分配独立 ID，同一文案也可作为一次新的用户反馈。 */
export interface FeedbackEvent {
  id: number;
  level: FeedbackLevel;
  message: string;
}

export type FeedbackListener = (event: FeedbackEvent) => void;
