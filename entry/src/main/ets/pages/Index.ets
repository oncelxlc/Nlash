import { display, window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { FeedbackEvent, FeedbackLevel } from '../models/FeedbackModels';
import { ConfigurationPage } from '../components/ConfigurationPage';
import { ConnectionsPage } from '../components/ConnectionsPage';
import { DashboardPage } from '../components/DashboardPage';
import { NavigationBasePage } from '../components/NavigationBasePage';
import { ProxyPage } from '../components/ProxyPage';
import { RequestsPage } from '../components/RequestsPage';
import { SettingsPage } from '../components/SettingsPage';
import {
  AppPage,
  BOTTOM_NAV_PAGES,
  NavigationLayout,
  resolveNavigationLayout,
  SIDE_NAV_PAGES
} from '../models/NavigationModels';
import { AppNavigationState, AppRoute } from '../navigation/AppNavigationState';
import { feedbackService } from '../services/FeedbackService';
import { configurationEditorService } from '../services/ConfigurationEditorService';
import { navigationIntentService } from '../services/NavigationIntentService';

@Entry
@Component
struct Index {
  @State navigationState: AppNavigationState = new AppNavigationState();
  @State navigationLayout: NavigationLayout = NavigationLayout.BOTTOM;
  @State isFoldable: boolean = false;
  @State foldStatus: display.FoldStatus = display.FoldStatus.FOLD_STATUS_UNKNOWN;
  @State windowStatus: window.WindowStatusType = window.WindowStatusType.UNDEFINED;
  private foldListenerRegistered: boolean = false;
  private windowStatusListenerRegistered: boolean = false;
  private mainWindow: window.Window | undefined = undefined;
  private unsubscribeFeedback: (() => void) | undefined = undefined;
  private unsubscribeNavigationIntent: (() => void) | undefined = undefined;

  private readonly foldStatusChangeHandler = (status: display.FoldStatus): void => {
    this.foldStatus = status;
    this.updateNavigationLayout();
  };

  private readonly windowStatusChangeHandler = (status: window.WindowStatusType): void => {
    this.windowStatus = status;
    this.updateNavigationLayout();
  };

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
    this.registerResponsiveListeners();
  }

  aboutToDisappear(): void {
    this.unsubscribeFeedback?.();
    this.unsubscribeFeedback = undefined;
    this.unsubscribeNavigationIntent?.();
    this.unsubscribeNavigationIntent = undefined;
    this.unregisterResponsiveListeners();
  }

  private registerResponsiveListeners(): void {
    try {
      this.isFoldable = display.isFoldable();
      if (this.isFoldable) {
        this.foldStatus = display.getFoldStatus();
        display.on('foldStatusChange', this.foldStatusChangeHandler);
        this.foldListenerRegistered = true;
      }
    } catch (error) {
      this.isFoldable = false;
      this.foldStatus = display.FoldStatus.FOLD_STATUS_UNKNOWN;
    }
    this.registerWindowStatusListener();
    this.updateNavigationLayout();
  }

  private registerWindowStatusListener(): void {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
      if (context === undefined) {
        return;
      }
      this.mainWindow = context.windowStage.getMainWindowSync();
      this.windowStatus = this.mainWindow.getWindowStatus();
      this.mainWindow.on('windowStatusChange', this.windowStatusChangeHandler);
      this.windowStatusListenerRegistered = true;
    } catch (error) {
      this.mainWindow = undefined;
      this.windowStatus = window.WindowStatusType.UNDEFINED;
    }
  }

  private unregisterResponsiveListeners(): void {
    if (this.foldListenerRegistered) {
      try {
        display.off('foldStatusChange', this.foldStatusChangeHandler);
      } catch (error) {
      }
      this.foldListenerRegistered = false;
    }
    if (this.windowStatusListenerRegistered && this.mainWindow !== undefined) {
      try {
        this.mainWindow.off('windowStatusChange', this.windowStatusChangeHandler);
      } catch (error) {
      }
    }
    this.windowStatusListenerRegistered = false;
    this.mainWindow = undefined;
  }

  private updateNavigationLayout(): void {
    this.navigationLayout = resolveNavigationLayout(this.isFoldable, this.isExpandedFold(), this.isSmallWindow());
  }

  private isExpandedFold(): boolean {
    return this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED ||
      this.foldStatus === display.FoldStatus.FOLD_STATUS_EXPANDED_WITH_SECOND_EXPANDED;
  }

  private isSmallWindow(): boolean {
    return this.windowStatus === window.WindowStatusType.FLOATING ||
      this.windowStatus === window.WindowStatusType.SPLIT_SCREEN;
  }

  private selectPage(page: AppPage): void {
    this.navigationState.selectPage(page);
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

  private getNavigationColor(page: AppPage): ResourceColor {
    return this.navigationState.selectedPage === page ?
      $r('app.color.nav_selected') : $r('app.color.nav_unselected');
  }

  private handlePrimaryBack(page: AppPage): boolean {
    if (page !== AppPage.DASHBOARD) {
      this.selectPage(AppPage.DASHBOARD);
      return true;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext | undefined;
    if (context !== undefined) {
      context.terminateSelf().catch((): void => {
      });
    }
    return true;
  }

  @Builder
  private destinationBuilder(name: string) {
    if (name === AppRoute.DASHBOARD) {
      NavDestination() {
        DashboardPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.app_background'))
      .onBackPressed((): boolean => this.handlePrimaryBack(AppPage.DASHBOARD))
    } else if (name === AppRoute.PROXY) {
      NavDestination() {
        ProxyPage({ forceExpanded: this.navigationLayout === NavigationLayout.SIDE })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.app_background'))
      .onBackPressed((): boolean => this.handlePrimaryBack(AppPage.PROXY))
    } else if (name === AppRoute.CONFIGURATION) {
      NavDestination() {
        ConfigurationPage({ forceExpanded: this.navigationLayout === NavigationLayout.SIDE })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.app_background'))
      .onBackPressed((): boolean => {
        if (configurationEditorService.handleBack()) {
          return true;
        }
        return this.handlePrimaryBack(AppPage.CONFIGURATION);
      })
    } else if (name === AppRoute.REQUESTS) {
      NavDestination() {
        RequestsPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.app_background'))
      .onBackPressed((): boolean => this.handlePrimaryBack(AppPage.REQUESTS))
    } else if (name === AppRoute.CONNECTIONS) {
      NavDestination() {
        ConnectionsPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.app_background'))
      .onBackPressed((): boolean => this.handlePrimaryBack(AppPage.CONNECTIONS))
    } else if (name === AppRoute.SETTINGS) {
      NavDestination() {
        SettingsPage()
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.app_background'))
      .onBackPressed((): boolean => this.handlePrimaryBack(AppPage.SETTINGS))
    }
  }

  @Builder
  private sideNavigationItem(page: AppPage) {
    Column({ space: 2 }) {
      Image(this.getPageIcon(page))
        .width(22)
        .height(22)
        .fillColor(this.getNavigationColor(page))
      Text(this.getPageLabel(page))
        .fontSize(13)
        .fontWeight(this.navigationState.selectedPage === page ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.getNavigationColor(page))
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('100%')
    .height(56)
    .borderRadius(12)
    .backgroundColor(this.navigationState.selectedPage === page ?
      $r('app.color.nav_selected_background') : Color.Transparent)
    .accessibilityText(this.getPageLabel(page))
    .onClick((): void => {
      this.selectPage(page);
    })
  }

  @Builder
  private sideNavigation() {
    Column({ space: 2 }) {
      Text($r('app.string.app_title'))
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.content_primary'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .padding({ bottom: 6 })
      ForEach(SIDE_NAV_PAGES, (page: AppPage) => {
        this.sideNavigationItem(page)
      }, (page: AppPage): string => page.toString())
    }
    .width(this.navigationLayout === NavigationLayout.SIDE ? 90 : 0)
    .height('100%')
    .padding(this.navigationLayout === NavigationLayout.SIDE ? { top: 12, left: 8, right: 8 } : 0)
    .visibility(this.navigationLayout === NavigationLayout.SIDE ? Visibility.Visible : Visibility.Hidden)
    .backgroundColor($r('app.color.nav_surface'))
    .border({ width: { right: 1 }, color: $r('app.color.nav_divider') })
    .zIndex(1)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private bottomNavigationItem(page: AppPage) {
    Column({ space: 4 }) {
      Image(this.getPageIcon(page))
        .width(24)
        .height(24)
        .fillColor(this.getNavigationColor(page))
      Text(this.getPageLabel(page))
        .fontSize(12)
        .fontWeight(this.navigationState.selectedPage === page ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.getNavigationColor(page))
        .maxLines(1)
    }
    .justifyContent(FlexAlign.Center)
    .height(64)
    .layoutWeight(1)
    .borderRadius(12)
    .backgroundColor(this.navigationState.selectedPage === page ?
      $r('app.color.nav_selected_background') : Color.Transparent)
    .accessibilityText(this.getPageLabel(page))
    .onClick((): void => {
      this.selectPage(page);
    })
  }

  @Builder
  private bottomNavigation() {
    Row() {
      ForEach(BOTTOM_NAV_PAGES, (page: AppPage) => {
        this.bottomNavigationItem(page)
      }, (page: AppPage): string => page.toString())
    }
    .width('100%')
    .height(this.navigationLayout === NavigationLayout.BOTTOM ? 72 : 0)
    .padding(this.navigationLayout === NavigationLayout.BOTTOM ? { top: 4, bottom: 4, left: 8, right: 8 } : 0)
    .visibility(this.navigationLayout === NavigationLayout.BOTTOM ? Visibility.Visible : Visibility.Hidden)
    .backgroundColor($r('app.color.nav_surface'))
    .border({ width: { top: 1 }, color: $r('app.color.nav_divider') })
    .zIndex(1)
    .expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.BOTTOM])
  }

  build() {
    Row() {
      this.sideNavigation()
      Column() {
        Navigation(this.navigationState.pathStack) {
          NavigationBasePage()
        }
        .layoutWeight(1)
        .width('100%')
        .height('100%')
        .hideTitleBar(true)
        .mode(NavigationMode.Stack)
        .navDestination(this.destinationBuilder)
        .backgroundColor($r('app.color.app_background'))
        this.bottomNavigation()
      }
      .height('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .expandSafeArea([SafeAreaType.SYSTEM],[SafeAreaEdge.BOTTOM])
  }
}
