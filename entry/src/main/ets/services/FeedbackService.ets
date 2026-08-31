import { FeedbackEvent, FeedbackLevel, FeedbackListener } from '../model/FeedbackModels';

const DEFAULT_DEDUPE_WINDOW_MS = 3000;

export class FeedbackService {
  private nextId: number = 1;
  private listeners: Set<FeedbackListener> = new Set<FeedbackListener>();
  private lastSignature: string = '';
  private lastPublishedAt: number = 0;

  subscribe(listener: FeedbackListener): () => void {
    this.listeners.add(listener);
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  info(message: string): void {
    this.publish(FeedbackLevel.INFO, message);
  }

  success(message: string): void {
    this.publish(FeedbackLevel.SUCCESS, message);
  }

  warning(message: string): void {
    this.publish(FeedbackLevel.WARNING, message);
  }

  error(message: string): void {
    this.publish(FeedbackLevel.ERROR, message);
  }

  publishDeduplicated(level: FeedbackLevel, message: string,
    windowMs: number = DEFAULT_DEDUPE_WINDOW_MS): void {
    const normalized = message.trim();
    if (normalized.length === 0) {
      return;
    }
    const now = Date.now();
    const signature = `${level}:${normalized}`;
    if (signature === this.lastSignature && now - this.lastPublishedAt < windowMs) {
      return;
    }
    this.publish(level, normalized);
  }

  private publish(level: FeedbackLevel, message: string): void {
    const normalized = message.trim();
    if (normalized.length === 0) {
      return;
    }
    const event: FeedbackEvent = {
      id: this.nextId,
      level: level,
      message: normalized
    };
    this.nextId += 1;
    this.lastSignature = `${level}:${normalized}`;
    this.lastPublishedAt = Date.now();
    this.listeners.forEach((listener: FeedbackListener): void => listener(event));
  }
}

export const feedbackService = new FeedbackService();
