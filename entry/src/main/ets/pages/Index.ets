import { common } from '@kit.AbilityKit';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { FeedbackEvent, FeedbackLevel } from '../model/FeedbackModels';
import { ConfigurationPage } from '../view/ConfigurationPage';
import { ActivityPage } from '../view/ActivityPage';
import { DashboardPage } from '../view/DashboardPage';
import { ProxyPage } from '../view/ProxyPage';
import { SettingsPage } from '../view/SettingsPage';
import { ActivityTab, AppPage } from '../model/NavigationModels';
import { NAVIGATION_PAGES } from '../constants/NavigationConstants';
import { AppNavigationState } from '../navigation/AppNavigationState';
import { feedbackService } from '../services/FeedbackService';
import { configurationEditorService } from '../services/ConfigurationEditorService';
import { navigationIntentService } from '../services/NavigationIntentService';
import { NavigationTransition, SettingsStoreSnapshot } from '../model/SettingsModels';
import { settingsStore } from '../stores/SettingsStore';
import { PageEntrance } from '../components/PageEntrance';

/** 应用页面容器，统一导航、反馈展示及返回行为，并管理页面级订阅的释放。 */
@Entry
@Component
struct Index {
  @State navigationState: AppNavigationState = new AppNavigationState();
  @State navigationTransition: NavigationTransition = settingsStore.getSnapshot().settings.navigationTransition;
  @State entranceOffset: number = 24;
  private unsubscribeFeedback: (() => void) | undefined = undefined;
  private unsubscribeNavigationIntent: (() => void) | undefined = undefined;
  private unsubscribeSettings: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribeSettings = settingsStore.subscribe((snapshot: SettingsStoreSnapshot): void => {
      this.navigationTransition = snapshot.settings.navigationTransition;
    });
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
    this.unsubscribeSettings?.();
    this.unsubscribeSettings = undefined;
  }

  /** 返回优先级：活动页返回设置 → 编辑器关闭确认 → 仪表盘 → 后台。 */
  onBackPress(): boolean {
    if (this.navigationState.activityOpen) {
      this.selectPage(AppPage.SETTINGS);
      return true;
    }
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
    // 程序切到设置时的标签回调不能关闭刚打开的活动页。
    if (page !== undefined && page !== this.navigationState.selectedPage) {
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
      case AppPage.ACTIVITY:
        return $r('app.string.nav_activity');
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
      case AppPage.ACTIVITY:
        return $r('app.media.nav_activity');
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

  // 仪表盘返回只切入后台，保留现有 UI Ability，避免返回操作触发整套入口重建。
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
    } else if (page === AppPage.ACTIVITY) {
      ActivityPage({
        selectedTab: this.navigationState.activityTab,
        onTabChange: (tab: ActivityTab): void => { this.navigationState.selectActivityTab(tab); },
        onBack: (): void => { this.selectPage(AppPage.SETTINGS); }
      })
    } else if (page === AppPage.SETTINGS) {
      SettingsPage({ onOpenActivity: (): void => { this.selectPage(AppPage.ACTIVITY); } })
    }
  }

  build() {
    Stack() {
      HdsTabs({
        barPosition: BarPosition.End,
        index: NAVIGATION_PAGES.indexOf(this.navigationState.selectedPage)
      }) {
        ForEach(NAVIGATION_PAGES, (page: AppPage) => {
          TabContent() {
            PageEntrance({
              effect: this.navigationTransition, initialOffset: this.entranceOffset,
              content: (): void => { this.pageContent(page); }
            })
          }
          .tabBar(this.getTabBarStyle(page))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }, (page: AppPage): string => page.toString())
      }
      .vertical(false)
      .scrollable(false)
      .animationDuration(0)
      .onContentWillChange((from: number, to: number): boolean => {
        this.entranceOffset = to > from ? 24 : -24;
        return true;
      })
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
      // 保留设置页的输入草稿与滚动位置，同时隐藏一级导航。
      .visibility(this.navigationState.activityOpen ? Visibility.Hidden : Visibility.Visible)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

      if (this.navigationState.activityOpen) {
        PageEntrance({
          effect: this.navigationTransition,
          content: (): void => { this.pageContent(AppPage.ACTIVITY); }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
