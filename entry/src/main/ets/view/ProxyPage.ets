import {
  ProxyDelayOperationSnapshot,
  ProxyGroupSnapshot,
  ProxyNodeSnapshot,
  ProxySelection,
  ProxySnapshotSource,
  RuntimeStoreSnapshot
} from '../model/RuntimeModels';
import { proxyNodeRenderKey, visibleProxyGroups } from '../utils/RuntimeUtils';
import { AppSettings, SettingsStoreSnapshot } from '../model/SettingsModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveResponsiveMetrics, resolveContentWidth } from '../utils/ResponsiveUtils';
import {
  CONTROL_HEIGHT, HEADER_ACTION_SIZE, HEADER_ACTION_ICON_SIZE, FLOATING_NAVIGATION_INSET,
  CAPTION_FONT_SIZE
} from '../constants/UiConstants';
import { PageHeader } from '../components/PageHeader';
import { EmptyStateBackground } from '../components/EmptyStateBackground';
import { textTabBar } from '../components/TextTabBar';
import { StatusBadge } from '../components/StatusBadge';
import { ProxyNodeCard } from '../components/ProxyNodeCard';

@Component
export struct ProxyPage {
  @Prop forceExpanded: boolean = false;
  @State coreAvailable: boolean = false;
  private selecting: boolean = false;
  @State previewLoading: boolean = false;
  @State groups: ProxyGroupSnapshot[] = [];
  @State selections: ProxySelection[] = [];
  @State source: ProxySnapshotSource = ProxySnapshotSource.NONE;
  @State selectedGroup: string = '';
  @State delayOperations: ProxyDelayOperationSnapshot[] = [];
  @State settings: AppSettings = settingsStore.getSnapshot().settings;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private proxyGroups: ProxyGroupSnapshot[] = [];
  private unsubscribeRuntime: (() => void) | undefined = undefined;
  private unsubscribeSettings: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.coreAvailable = snapshot.coreAvailable;
      this.previewLoading = snapshot.previewLoading;
      const groups = visibleProxyGroups(snapshot.proxies, snapshot.proxyMode);
      if (groups.length !== this.proxyGroups.length || groups.some((group: ProxyGroupSnapshot, index: number): boolean =>
        group !== this.proxyGroups[index])) {
        this.proxyGroups = groups;
        this.groups = groups;
      }
      if (snapshot.proxySelections.length !== this.selections.length ||
        snapshot.proxySelections.some((selection: ProxySelection, index: number): boolean =>
          selection.group !== this.selections[index]?.group || selection.proxy !== this.selections[index]?.proxy)) {
        this.selections = snapshot.proxySelections;
      }
      this.source = snapshot.proxySource;
      this.selectedGroup = snapshot.selectedProxyGroup;
      if (snapshot.delayOperations.length !== this.delayOperations.length ||
        snapshot.delayOperations.some((operation: ProxyDelayOperationSnapshot, index: number): boolean =>
          operation.operationId !== this.delayOperations[index]?.operationId ||
          operation.pendingProxies.join('\n') !== this.delayOperations[index]?.pendingProxies.join('\n'))) {
        this.delayOperations = snapshot.delayOperations;
      }
    });
    this.unsubscribeSettings = settingsStore.subscribe((snapshot: SettingsStoreSnapshot): void => {
      this.settings = snapshot.settings;
    });
    runtimeStore.refresh();
  }

  aboutToDisappear(): void {
    this.unsubscribeRuntime?.();
    this.unsubscribeRuntime = undefined;
    this.unsubscribeSettings?.();
    this.unsubscribeSettings = undefined;
  }

  private updateWidth(width: Length): void {
    this.metrics = resolveResponsiveMetrics(resolveContentWidth(width), this.forceExpanded);
  }

  private currentGroup(): ProxyGroupSnapshot | undefined {
    return this.groups.find((group: ProxyGroupSnapshot): boolean => group.name === this.selectedGroup);
  }

  private preselectedNode(group: string): string {
    return this.selections.find((selection: ProxySelection): boolean => selection.group === group)?.proxy ?? '';
  }

  private isNodeSelected(node: ProxyNodeSnapshot): boolean {
    const group = this.currentGroup();
    if (this.coreAvailable) {
      return group?.selected === node.name;
    }
    const preselected = this.preselectedNode(group?.name ?? '');
    return (preselected.length > 0 ? preselected : (group?.selected ?? '')) === node.name;
  }

  private isNodeTesting(node: ProxyNodeSnapshot): boolean {
    const groupName = this.currentGroup()?.name ?? '';
    return this.delayOperations.some((operation: ProxyDelayOperationSnapshot): boolean =>
      operation.group === groupName && operation.pendingProxies.includes(node.name));
  }

  private isGroupTesting(): boolean {
    const groupName = this.currentGroup()?.name ?? '';
    return this.delayOperations.some((operation: ProxyDelayOperationSnapshot): boolean =>
      operation.group === groupName && operation.proxy.length === 0);
  }

  private async selectNode(node: ProxyNodeSnapshot): Promise<void> {
    const group = this.currentGroup();
    if (group !== undefined && group.selectable && !this.selecting) {
      this.selecting = true;
      try {
        await runtimeStore.selectProxy(group.name, node.name);
        feedbackService.success(`已选择 ${node.name}`);
      } catch (error) {
        feedbackService.error(this.errorMessage(error));
      } finally {
        this.selecting = false;
      }
    }
  }

  private async testNode(node: ProxyNodeSnapshot): Promise<void> {
    const group = this.currentGroup();
    if (group !== undefined) {
      try {
        await runtimeStore.testDelay(group.name, node.name, this.settings.delayTestUrl);
      } catch (error) {
        feedbackService.error(this.errorMessage(error));
      }
    }
  }

  private async testCurrentGroup(): Promise<void> {
    const group = this.currentGroup();
    if (group === undefined) {
      return;
    }
    try {
      await runtimeStore.testGroupDelay(group.name, this.settings.delayTestUrl);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async selectGroup(group: string): Promise<void> {
    try {
      await runtimeStore.selectProxyGroup(group);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : '代理操作失败';
  }

  @Builder
  private testGroupButton() {
    Button({ type: ButtonType.Normal }) {
      if (this.isGroupTesting()) {
        LoadingProgress().width(HEADER_ACTION_ICON_SIZE).height(HEADER_ACTION_ICON_SIZE).color($r('app.color.nav_selected'))
      } else {
        Image($r('app.media.action_refresh')).width(HEADER_ACTION_ICON_SIZE).height(HEADER_ACTION_ICON_SIZE)
          .fillColor($r('app.color.nav_selected'))
      }
    }
    .width(HEADER_ACTION_SIZE).height(HEADER_ACTION_SIZE)
    .responseRegion({ x: -8, y: -8, width: CONTROL_HEIGHT, height: CONTROL_HEIGHT })
    .padding(0).borderRadius(8)
    .backgroundColor($r('app.color.nav_selected_background'))
    .enabled(!this.isGroupTesting() && !this.previewLoading && this.currentGroup() !== undefined)
    .accessibilityText(this.isGroupTesting() ? '当前代理组正在测速' : `测试代理组 ${this.selectedGroup} 的节点延迟`)
    .onClick((): void => { this.testCurrentGroup(); })
  }

  @Builder
  private groupContent() {
    Column({ space: 16 }) {
      Text(`${this.selectedGroup} · ${this.currentGroup()?.nodes.length ?? 0} 个节点`)
        .fontSize(CAPTION_FONT_SIZE)
        .fontColor($r('app.color.content_secondary'))
        .width('100%')
        .padding({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
      Stack() {
        if ((this.currentGroup()?.nodes.length ?? 0) === 0) {
          EmptyStateBackground({
            icon: $r('app.media.nav_proxy'), title: '当前代理组暂无节点', description: '尝试其他代理组，或更新活动配置。'
          })
        }
        Grid() {
          ForEach(this.currentGroup()?.nodes ?? [], (node: ProxyNodeSnapshot, index: number) => {
            GridItem() {
              ProxyNodeCard({
                // Resolve from state so a stable key does not retain the original node.
                node: this.currentGroup()?.nodes[index] ?? node,
                selected: this.isNodeSelected(node),
                canSelect: this.currentGroup()?.selectable === true,
                testing: this.isNodeTesting(node),
                canTest: !this.previewLoading,
                onSelect: (): void => { this.selectNode(node); },
                onTest: (): void => { this.testNode(node); }
              })
            }
          }, (node: ProxyNodeSnapshot): string => `${this.selectedGroup.length}:${this.selectedGroup}:${proxyNodeRenderKey(node)}`)
        }
        .columnsTemplate(this.metrics.proxyColumns)
        .columnsGap(this.metrics.cardGap)
        .rowsGap(this.metrics.cardGap)
        .width('100%').height('100%')
        .contentEndOffset(this.metrics.pagePadding + FLOATING_NAVIGATION_INSET)
        .scrollBar(BarState.Off)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
      .width('100%').layoutWeight(1)
      .padding({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%').height('100%').padding({ top: 8 })
  }

  @Builder
  private mainContent() {
    Column({ space: 16 }) {
      PageHeader({
        title: $r('app.string.nav_proxy'), contentPadding: this.metrics.pagePadding,
        actions: (): void => { this.testGroupButton(); }
      })
      Row({ space: 8 }) {
        StatusBadge({
          text: this.source === ProxySnapshotSource.RUNTIME ? '运行中' :
            (this.source === ProxySnapshotSource.CONFIG ? '配置预览' : '无配置'),
          active: this.coreAvailable
        })
        Text(this.currentGroup()?.selectable === false ? '当前代理组由规则自动选择' : '点击节点选择，点击延迟单独测速')
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
      if (this.groups.length === 0) {
        Stack() {
          EmptyStateBackground({
            icon: $r('app.media.nav_proxy'),
            title: this.previewLoading ? '正在解析活动配置…' : '暂无可用代理组',
            description: this.previewLoading ? '解析完成后会显示节点。' : '在配置页添加并选择一份有效配置后，即可查看节点。'
          })
        }
        .width('100%').layoutWeight(1)
        .padding({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
      } else {
        Tabs({ index: this.groups.findIndex((group: ProxyGroupSnapshot): boolean => group.name === this.selectedGroup) }) {
          ForEach(this.groups, (group: ProxyGroupSnapshot) => {
            TabContent() { this.groupContent() }
              .tabBar(textTabBar(group.name))
          }, (group: ProxyGroupSnapshot): string => group.name)
        }
        .barMode(BarMode.Scrollable, { margin: this.metrics.pagePadding })
        .barHeight(CONTROL_HEIGHT)
        .barBackgroundColor(Color.Transparent)
        .divider(null)
        .scrollable(false)
        .animationDuration(0)
        .cachedMaxCount(0, TabsCacheMode.CACHE_LATEST_SWITCHED)
        .onChange((index: number): void => {
          const group = this.groups[index];
          if (group !== undefined && group.name !== this.selectedGroup) { this.selectGroup(group.name); }
        })
        .width('100%').layoutWeight(1)
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
  }

  build() {
    Column() {
      this.mainContent()
    }
    .width('100%').height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_old: Area, area: Area): void => { this.updateWidth(area.width); })
  }
}
