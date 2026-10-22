import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { common } from '@kit.AbilityKit';
import { HdsTabs, hdsMaterial } from '@kit.UIDesignKit';
import { FeedbackEvent, FeedbackLevel } from '../model/FeedbackModels';
import { ConfigurationPage } from '../view/ConfigurationPage';
import { ActivityPage } from '../view/ActivityPage';
import { DashboardPage } from '../view/DashboardPage';
import { ProxyPage } from '../view/ProxyPage';
import { SettingsPage } from '../view/SettingsPage';
import { ThemePage } from '../view/ThemePage';
import { GeneralPage } from '../view/GeneralPage';
import { AboutPage } from '../view/AboutPage';
import { LogsPage } from '../view/LogsPage';
import { AppPage } from '../model/NavigationModels';
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
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @StorageProp('appForeground') foreground: boolean = false;
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

  /** 返回优先级：二级页返回设置 → 编辑器关闭确认 → 仪表盘 → 后台。 */
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
    this.entranceOffset = page > this.navigationState.selectedPage ? 24 : -24;
    this.navigationState.selectPage(page);
  }

  private activePage(): AppPage {
    return this.navigationState.activityOpen ? this.navigationState.detailPage : this.navigationState.selectedPage;
  }

  private isPageActive(page: AppPage): boolean { return this.foreground && this.activePage() === page; }

  private selectTab(index: number): void {
    const page = NAVIGATION_PAGES[index];
    // 程序切到设置时的标签回调不能关闭刚打开的二级页。
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
      case AppPage.THEME:
      case AppPage.GENERAL:
      case AppPage.ABOUT:
      case AppPage.LOGS:
        return $r('app.string.nav_settings');
      case AppPage.ACTIVITY:
      case AppPage.DNS:
      case AppPage.RESOURCES:
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
      case AppPage.THEME:
      case AppPage.GENERAL:
      case AppPage.ABOUT:
      case AppPage.LOGS:
        return $r('app.media.nav_settings');
      case AppPage.ACTIVITY:
        return $r('app.media.nav_activity');
      case AppPage.DNS:
        return $r('app.media.nav_dns');
      case AppPage.RESOURCES:
        return $r('app.media.nav_resources');
    }
  }

  private getTabBarStyle(page: AppPage): BottomTabBarStyle {
    return new BottomTabBarStyle(this.getPageIcon(page), this.getPageLabel(page))
      .iconStyle({
        selectedColor: this.theme.accent,
        unselectedColor: $r('app.color.nav_unselected')
      })
      .labelStyle({
        selectedColor: this.theme.accent,
        unselectedColor: $r('app.color.nav_unselected'),
        font: { size: themeFontSize(12, this.theme), family: this.theme.fontFamily }
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
      DashboardPage({ isActive: this.isPageActive(page) })
    } else if (page === AppPage.PROXY) {
      ProxyPage({ isActive: this.isPageActive(page) })
    } else if (page === AppPage.CONFIGURATION) {
      ConfigurationPage()
    } else if (page === AppPage.THEME) {
      ThemePage({ onBack: (): void => { this.selectPage(AppPage.SETTINGS); } })
    } else if (page === AppPage.GENERAL) {
      GeneralPage({ isActive: this.isPageActive(page), onBack: (): void => { this.selectPage(AppPage.SETTINGS); } })
    } else if (page === AppPage.ABOUT) {
      AboutPage({ onBack: (): void => { this.selectPage(AppPage.SETTINGS); } })
    } else if (page === AppPage.LOGS) {
      LogsPage({ isActive: this.isPageActive(page), onBack: (): void => { this.selectPage(AppPage.SETTINGS); } })
    } else if (page === AppPage.SETTINGS) {
      SettingsPage({
        onOpenPage: (destination: AppPage): void => { this.selectPage(destination); } })
    } else {
      ActivityPage({ page: page, isActive: this.isPageActive(page),
        onBack: (): void => { this.selectPage(AppPage.SETTINGS); } })
    }
  }

  @Builder
  private applicationContent() {
    Stack() {
      HdsTabs({
        barPosition: BarPosition.End,
        index: NAVIGATION_PAGES.indexOf(this.navigationState.selectedPage)
      }) {
        ForEach(NAVIGATION_PAGES, (page: AppPage) => {
          TabContent() {
            this.pageContent(page)
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
        this.selectTab(to);
        return true;
      })
      .barOverlap(true)
      .cachedMaxCount(NAVIGATION_PAGES.length - 1, TabsCacheMode.CACHE_LATEST_SWITCHED)
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

      ForEach(this.navigationState.visitedDetails, (page: AppPage) => {
        Column() { this.pageContent(page) }
          .width('100%').height('100%').backgroundColor(this.theme.background)
          .visibility(this.navigationState.activityOpen && this.navigationState.detailPage === page ?
            Visibility.Visible : Visibility.Hidden)
      }, (page: AppPage): string => page.toString())
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.background)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  build() {
    Stack() {
      PageEntrance({ pageKey: this.activePage(), effect: this.navigationTransition,
        initialOffset: this.entranceOffset, content: (): void => { this.applicationContent(); } })
    }.width('100%').height('100%').backgroundColor(this.theme.background)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
