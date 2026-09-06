import { common } from '@kit.AbilityKit';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { FeedbackEvent, FeedbackLevel } from '../model/FeedbackModels';
import { ConfigurationPage } from '../view/ConfigurationPage';
import { ConnectionsPage } from '../view/ConnectionsPage';
import { DashboardPage } from '../view/DashboardPage';
import { ProxyPage } from '../view/ProxyPage';
import { RequestsPage } from '../view/RequestsPage';
import { SettingsPage } from '../view/SettingsPage';
import { AppPage } from '../model/NavigationModels';
import { NAVIGATION_PAGES } from '../constants/NavigationConstants';
import { AppNavigationState } from '../navigation/AppNavigationState';
import { feedbackService } from '../services/FeedbackService';
import { configurationEditorService } from '../services/ConfigurationEditorService';
import { navigationIntentService } from '../services/NavigationIntentService';

@Entry
@Component
struct Index {
  @State navigationState: AppNavigationState = new AppNavigationState();
  private unsubscribeFeedback: (() => void) | undefined = undefined;
  private unsubscribeNavigationIntent: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribeFeedback = feedbackService.subscribe((event: FeedbackEvent): void => {
      this.getUIContext().getPromptAction().showToast({
        message: event.message,
        duration: event.level === FeedbackLevel.WARNING || event.level === FeedbackLevel.ERROR ? 3500 : 2000
      });
    });
    this.unsubscribeNavigationIntent = navigationIntentService.subscribe((page: AppPage): void => {
      this.selectPage(page);
    });
  }

  aboutToDisappear(): void {
    this.unsubscribeFeedback?.();
    this.unsubscribeFeedback = undefined;
    this.unsubscribeNavigationIntent?.();
    this.unsubscribeNavigationIntent = undefined;
  }

  onBackPress(): boolean {
    if (this.navigationState.selectedPage === AppPage.CONFIGURATION && configurationEditorService.handleBack()) {
      return true;
    }
    return this.handlePrimaryBack(this.navigationState.selectedPage);
  }

  private selectPage(page: AppPage): void {
    this.navigationState.selectPage(page);
  }

  private selectTab(index: number): void {
    const page = NAVIGATION_PAGES[index];
    if (page !== undefined) {
      this.selectPage(page);
    }
  }

  private getPageLabel(page: AppPage): Resource {
    switch (page) {
      case AppPage.DASHBOARD:
        return $r('app.string.nav_dashboard');
      case AppPage.PROXY:
        return $r('app.string.nav_proxy');
      case AppPage.CONFIGURATION:
        return $r('app.string.nav_configuration');
      case AppPage.REQUESTS:
        return $r('app.string.nav_requests');
      case AppPage.CONNECTIONS:
        return $r('app.string.nav_connections');
      case AppPage.SETTINGS:
        return $r('app.string.nav_settings');
    }
  }

  private getPageIcon(page: AppPage): Resource {
    switch (page) {
      case AppPage.DASHBOARD:
        return $r('app.media.nav_dashboard');
      case AppPage.PROXY:
        return $r('app.media.nav_proxy');
      case AppPage.CONFIGURATION:
        return $r('app.media.nav_configuration');
      case AppPage.REQUESTS:
        return $r('app.media.nav_requests');
      case AppPage.CONNECTIONS:
        return $r('app.media.nav_connections');
      case AppPage.SETTINGS:
        return $r('app.media.nav_settings');
    }
  }

  private getTabBarStyle(page: AppPage): BottomTabBarStyle {
    return new BottomTabBarStyle(this.getPageIcon(page), this.getPageLabel(page))
      .iconStyle({
        selectedColor: $r('app.color.nav_selected'),
        unselectedColor: $r('app.color.nav_unselected')
      })
      .labelStyle({
        selectedColor: $r('app.color.nav_selected'),
        unselectedColor: $r('app.color.nav_unselected')
      });
  }

  private handlePrimaryBack(page: AppPage): boolean {
    if (page !== AppPage.DASHBOARD) {
      this.selectPage(AppPage.DASHBOARD);
      return true;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context !== undefined) {
      context.moveAbilityToBackground().catch((): void => {
        feedbackService.error('切换到后台失败，请重试或使用系统桌面手势');
      });
    }
    return true;
  }

  @Builder
  private pageContent(page: AppPage) {
    if (page === AppPage.DASHBOARD) {
      DashboardPage()
    } else if (page === AppPage.PROXY) {
      ProxyPage()
    } else if (page === AppPage.CONFIGURATION) {
      ConfigurationPage()
    } else if (page === AppPage.REQUESTS) {
      RequestsPage()
    } else if (page === AppPage.CONNECTIONS) {
      ConnectionsPage()
    } else if (page === AppPage.SETTINGS) {
      SettingsPage()
    }
  }

  build() {
    HdsTabs({
      barPosition: BarPosition.End,
      index: NAVIGATION_PAGES.indexOf(this.navigationState.selectedPage)
    }) {
      ForEach(NAVIGATION_PAGES, (page: AppPage) => {
        TabContent() {
          this.pageContent(page)
        }
        .tabBar(this.getTabBarStyle(page))
      }, (page: AppPage): string => page.toString())
    }
    .vertical(false)
    .scrollable(false)
    .barOverlap(true)
    .cachedMaxCount(0, TabsCacheMode.CACHE_LATEST_SWITCHED)
    .barFloatingStyle({
      adaptToHandedness: true,
      thermoCtrl: true,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      }
    })
    .onChange((index: number): void => {
      this.selectTab(index);
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
