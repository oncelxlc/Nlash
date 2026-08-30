import { AppPage } from '../models/NavigationModels';

export type NavigationIntentListener = (page: AppPage) => void;

class NavigationIntentService {
  private pendingPage: AppPage | undefined;
  private listeners: Set<NavigationIntentListener> = new Set<NavigationIntentListener>();

  publish(page: AppPage): void {
    if (this.listeners.size === 0) {
      this.pendingPage = page;
      return;
    }
    this.pendingPage = undefined;
    this.listeners.forEach((listener: NavigationIntentListener): void => listener(page));
  }

  subscribe(listener: NavigationIntentListener): () => void {
    this.listeners.add(listener);
    const pending = this.pendingPage;
    if (pending !== undefined) {
      this.pendingPage = undefined;
      listener(pending);
    }
    return (): void => {
      this.listeners.delete(listener);
    };
  }
}

export const navigationIntentService = new NavigationIntentService();
