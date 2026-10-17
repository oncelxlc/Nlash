import { AppPage } from '../model/NavigationModels';

export type NavigationIntentListener = (page: AppPage) => void;

/** 缓存页面挂载前到达的最后一个跳转意图，首个订阅者注册时消费一次。 */
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
