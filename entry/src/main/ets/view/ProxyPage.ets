import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import {
  ProxyDelayOperationSnapshot,
  ProxyGroupSnapshot,
  ProxyNodeSnapshot,
  ProxySelection,
  RuntimeStoreSnapshot
} from '../model/RuntimeModels';
import { filterProxyNodes, proxyNodeRenderKey, visibleProxyGroups } from '../utils/RuntimeUtils';
import { AppSettings, SettingsStoreSnapshot } from '../model/SettingsModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import {
  resolveResponsiveMetrics, resolveContentWidth, proxyGroupColumnCount, proxyNodeColumnCount
} from '../utils/ResponsiveUtils';
import { CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, CAPTION_FONT_SIZE } from '../constants/UiConstants';
import { PageHeader } from '../components/PageHeader';
import { FadingScrollLayout } from '../components/FadingScrollLayout';
import { EmptyStateBackground } from '../components/EmptyStateBackground';
import { ProxyNodeCard } from '../components/ProxyNodeCard';

/** 策略组可独立展开；节点选择、分组偏好和并发测速仍由 RuntimeStore 管理。 */
@Component
export struct ProxyPage {
  @StorageProp('appTheme') @Watch('onThemeChange') theme: AppTheme = DEFAULT_APP_THEME;
  @State headerInset: number = 0;
  @Prop forceExpanded: boolean = false;
  @State coreAvailable: boolean = false;
  private selecting: boolean = false;
  @State previewLoading: boolean = false;
  @State groups: ProxyGroupSnapshot[] = [];
  @State selections: ProxySelection[] = [];
  @State expandedGroups: string[] = [];
  @State searchVisible: boolean = false;
  @State query: string = '';
  @State delayOperations: ProxyDelayOperationSnapshot[] = [];
  @State settings: AppSettings = settingsStore.getSnapshot().settings;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  @State contentWidth: number = 0;
  @State fontScale: number = 1;
  private scrollers: ListScroller[] = [new ListScroller(), new ListScroller()];
  private proxyGroups: ProxyGroupSnapshot[] = [];
  private restoreSelectionPending: boolean = true;
  private entryGroup: string = '';
  private readonly restoreSelectionAfterLayout = (): void => {
    if (!this.restoreSelectionPending || this.contentWidth <= 0 || this.entryGroup.length === 0) { return; }
    const index = this.groups.findIndex((group: ProxyGroupSnapshot): boolean => group.name === this.entryGroup);
    if (index < 0 || !this.isExpanded(this.entryGroup)) { return; }
    this.restoreSelectionPending = false;
    this.getUIContext().getUIObserver().off('didLayout', this.restoreSelectionAfterLayout);
    this.locateSelected(this.groups[index], index % this.columnCount());
  };
  private unsubscribeRuntime: (() => void) | undefined = undefined;
  private unsubscribeSettings: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.restoreSelectionPending = true;
    this.entryGroup = '';
    this.getUIContext().getUIObserver().on('didLayout', this.restoreSelectionAfterLayout);
    this.fontScale = this.theme.fontScale || this.getUIContext().fp2px(1) / this.getUIContext().vp2px(1);
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.coreAvailable = snapshot.coreAvailable;
      this.previewLoading = snapshot.previewLoading;
      // 保留未变化的引用，避免定时刷新打断列表滚动。
      const groups = visibleProxyGroups(snapshot.proxies, snapshot.proxyMode);
      if (groups.length !== this.proxyGroups.length || groups.some((group: ProxyGroupSnapshot, index: number): boolean =>
        group !== this.proxyGroups[index])) {
        this.proxyGroups = groups;
        this.groups = groups;
        this.expandedGroups = this.expandedGroups.filter((name: string): boolean =>
          groups.some((group: ProxyGroupSnapshot): boolean => group.name === name));
      }
      if (snapshot.proxySelections.length !== this.selections.length ||
        snapshot.proxySelections.some((selection: ProxySelection, index: number): boolean =>
          selection.group !== this.selections[index]?.group || selection.proxy !== this.selections[index]?.proxy)) {
        this.selections = snapshot.proxySelections;
      }
      if (snapshot.delayOperations.length !== this.delayOperations.length ||
        snapshot.delayOperations.some((operation: ProxyDelayOperationSnapshot, index: number): boolean =>
          operation.operationId !== this.delayOperations[index]?.operationId ||
          operation.pendingProxies.join('\n') !== this.delayOperations[index]?.pendingProxies.join('\n'))) {
        this.delayOperations = snapshot.delayOperations;
      }
      // 等待配置和偏好加载完成；仅在本次进入时恢复，不跟随定时快照反复滚动。
      if (this.restoreSelectionPending && !this.previewLoading && this.entryGroup.length === 0 &&
        groups.some((group: ProxyGroupSnapshot): boolean => group.name === snapshot.selectedProxyGroup)) {
        this.entryGroup = snapshot.selectedProxyGroup;
        this.expandedGroups = [this.entryGroup];
      }
    });
    this.unsubscribeSettings = settingsStore.subscribe((snapshot: SettingsStoreSnapshot): void => {
      this.settings = snapshot.settings;
    });
    runtimeStore.refresh();
  }

  aboutToDisappear(): void {
    this.getUIContext().getUIObserver().off('didLayout', this.restoreSelectionAfterLayout);
    this.unsubscribeRuntime?.();
    this.unsubscribeRuntime = undefined;
    this.unsubscribeSettings?.();
    this.unsubscribeSettings = undefined;
  }

  private updateWidth(width: Length): void {
    this.contentWidth = resolveContentWidth(width);
    this.metrics = resolveResponsiveMetrics(this.contentWidth, this.forceExpanded);
    this.fontScale = this.theme.fontScale || this.getUIContext().fp2px(1) / this.getUIContext().vp2px(1);
  }

  private onThemeChange(): void { this.updateWidth(this.contentWidth); }

  private columnCount(): number {
    return proxyGroupColumnCount(this.contentWidth, this.fontScale);
  }

  private nodeColumnCount(): number {
    const width = (this.contentWidth - this.metrics.pagePadding * 2 -
      (this.columnCount() - 1) * this.metrics.cardGap) / this.columnCount();
    return proxyNodeColumnCount(width, this.fontScale);
  }

  private groupIndexes(column: number): number[] {
    return this.groups.map((_group: ProxyGroupSnapshot, index: number): number => index)
      .filter((index: number): boolean => this.query.trim().length === 0 ||
        this.groups[index].name.toLocaleLowerCase().includes(this.query.trim().toLocaleLowerCase()) ||
        filterProxyNodes(this.groups[index], this.query).length > 0)
      .filter((_index: number, visibleIndex: number): boolean => visibleIndex % this.columnCount() === column);
  }

  private isExpanded(group: string): boolean {
    return this.query.trim().length > 0 || this.expandedGroups.includes(group);
  }

  private selectedNode(group: ProxyGroupSnapshot): string {
    const preselected = this.selections.find((selection: ProxySelection): boolean => selection.group === group.name)?.proxy;
    return this.coreAvailable ? group.selected : (preselected || group.selected);
  }

  private isNodeTesting(group: string, node: string): boolean {
    return this.delayOperations.some((operation: ProxyDelayOperationSnapshot): boolean =>
      operation.group === group && operation.pendingProxies.includes(node));
  }

  private isGroupTesting(group: string): boolean {
    return this.delayOperations.some((operation: ProxyDelayOperationSnapshot): boolean =>
      operation.group === group && operation.proxy.length === 0);
  }

  private async selectNode(group: ProxyGroupSnapshot, node: ProxyNodeSnapshot): Promise<void> {
    if (!group.selectable || this.selecting) { return; }
    this.selecting = true;
    try {
      await runtimeStore.selectProxy(group.name, node.name);
      await runtimeStore.selectProxyGroup(group.name);
      feedbackService.success(`已选择 ${node.name}`);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    } finally {
      this.selecting = false;
    }
  }

  private async testNode(group: string, node: string): Promise<void> {
    try {
      await runtimeStore.testDelay(group, node, this.settings.delayTestUrl);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async testGroup(group: string): Promise<void> {
    try {
      await runtimeStore.testGroupDelay(group, this.settings.delayTestUrl);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async toggleGroup(group: string): Promise<void> {
    if (this.isExpanded(group)) {
      this.query = '';
      this.expandedGroups = this.expandedGroups.filter((name: string): boolean => name !== group);
      return;
    }
    this.expandedGroups = this.expandedGroups.concat(group);
    try {
      await runtimeStore.selectProxyGroup(group);
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private locateSelected(group: ProxyGroupSnapshot, column: number): void {
    const nodeIndex = filterProxyNodes(group, this.query)
      .findIndex((node: ProxyNodeSnapshot): boolean => node.name === this.selectedNode(group));
    const groupIndex = this.groupIndexes(column).findIndex((index: number): boolean => this.groups[index].name === group.name);
    if (nodeIndex >= 0 && groupIndex >= 0) {
      try {
        this.scrollers[column].scrollToItemInGroup(groupIndex, Math.floor(nodeIndex / this.nodeColumnCount()), false,
          ScrollAlign.CENTER);
      } catch (error) {
        feedbackService.error(this.errorMessage(error));
      }
    }
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ? exception.message : '代理操作失败';
  }

  @Builder
  private headerActions() {
    Row({ space: 8 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.action_search')).width(24).height(24)
          .fillColor($r('app.color.content_primary')).accessibilityLevel('no')
      }
      .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).backgroundColor(this.theme.surface)
      .accessibilityText(this.searchVisible ? '关闭代理搜索' : '搜索代理组和节点')
      .onClick((): void => { this.searchVisible = !this.searchVisible; this.query = ''; })
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.action_more')).width(24).height(24).rotate({ angle: 90 })
          .fillColor($r('app.color.content_primary')).accessibilityLevel('no')
      }
      .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT).backgroundColor(this.theme.surface)
      .accessibilityText('代理页面更多操作')
      .bindMenu([
        { value: '展开全部', action: (): void => {
          this.expandedGroups = this.groups.map((group: ProxyGroupSnapshot): string => group.name);
        } },
        { value: '收起全部', action: (): void => { this.query = ''; this.expandedGroups = []; } }
      ])
    }
  }

  @Builder
  private groupActions(group: ProxyGroupSnapshot, column: number) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Circle }) {
        Image($r('app.media.action_locate')).width(20).height(20)
          .fillColor($r('app.color.content_primary')).accessibilityLevel('no')
      }
      .width(44).height(44).backgroundColor(Color.Transparent)
      .enabled(filterProxyNodes(group, this.query).some((node: ProxyNodeSnapshot): boolean =>
        node.name === this.selectedNode(group)))
      .accessibilityText(`定位 ${group.name} 当前节点`)
      .onClick((): void => { this.locateSelected(group, column); })
      Button({ type: ButtonType.Circle }) {
        if (this.isGroupTesting(group.name)) {
          LoadingProgress().width(20).height(20).color(this.theme.accent)
        } else {
          Image($r('app.media.action_bolt')).width(20).height(20)
            .fillColor($r('app.color.content_primary')).accessibilityLevel('no')
        }
      }
      .width(44).height(44).backgroundColor(Color.Transparent)
      .enabled(!this.isGroupTesting(group.name) && !this.previewLoading && group.nodes.length > 0)
      .accessibilityText(this.isGroupTesting(group.name) ? `${group.name} 正在测速` : `测试 ${group.name} 全部节点延迟`)
      .onClick((): void => { this.testGroup(group.name); })
    }
    .borderRadius(24).backgroundColor(this.theme.inset)
  }

  @Builder
  private groupHeader(group: ProxyGroupSnapshot, column: number) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 12 }) {
            Text(Array.from(group.name)[0]?.toLocaleUpperCase() ?? '')
              .width(36).height(40).textAlign(TextAlign.Center).fontSize(themeFontSize(18, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.content_secondary')).borderRadius(14)
              .backgroundColor(this.theme.inset).accessibilityLevel('no')
            Column({ space: 4 }) {
              Text(group.name).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.content_primary')).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(this.selectedNode(group) || '暂无选择').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
                .fontColor($r('app.color.content_secondary')).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
            }
            .layoutWeight(1).alignItems(HorizontalAlign.Start)
          }
          .width('100%').constraintSize({ minHeight: CONTROL_HEIGHT })
        }
        .layoutWeight(1).padding(0).borderRadius(16).backgroundColor(Color.Transparent)
        .accessibilityText(`${group.name}，${group.type}，当前 ${this.selectedNode(group) || '暂无选择'}，` +
          (this.isExpanded(group.name) ? '已展开，点击收起' : '已收起，点击展开'))
        .onClick((): void => { this.toggleGroup(group.name); })
        if (this.isExpanded(group.name) && this.fontScale <= 1.2) {
          this.groupActions(group, column)
        } else if (!this.isExpanded(group.name)) {
          Text(group.type).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_secondary')).constraintSize({ maxWidth: 80 })
            .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.action_chevron_down')).width(24).height(24)
            .rotate({ angle: this.isExpanded(group.name) ? 180 : 0 })
            .fillColor($r('app.color.content_primary')).accessibilityLevel('no')
        }
        .width(44).height(44).backgroundColor(this.theme.inset)
        .accessibilityText(`${this.isExpanded(group.name) ? '收起' : '展开'} ${group.name}`)
        .onClick((): void => { this.toggleGroup(group.name); })
      }
      .width('100%')
      if (this.isExpanded(group.name) && this.fontScale > 1.2) {
        Row() { this.groupActions(group, column) }.width('100%').justifyContent(FlexAlign.End)
      }
    }
    .width('100%').padding(12).borderRadius(28).backgroundColor(this.theme.surface)
  }

  @Builder
  private groupColumn(column: number) {
    List({ space: this.metrics.cardGap, scroller: this.scrollers[column] }) {
      ForEach(this.groupIndexes(column), (groupIndex: number) => {
        ListItemGroup({ header: this.groupHeader(this.groups[groupIndex], column) }) {
          if (this.isExpanded(this.groups[groupIndex].name)) {
            ForEach(filterProxyNodes(this.groups[groupIndex], this.query)
              .filter((_node: ProxyNodeSnapshot, index: number): boolean => index % this.nodeColumnCount() === 0),
              (_node: ProxyNodeSnapshot, row: number) => {
                ListItem() {
                  Row({ space: 8 }) {
                    ForEach(filterProxyNodes(this.groups[groupIndex], this.query)
                      .slice(row * this.nodeColumnCount(), (row + 1) * this.nodeColumnCount()),
                      (node: ProxyNodeSnapshot, offset: number) => {
                        Column() {
                          // 从当前快照取值，使测速/选中变化无需更换列表 key。
                          ProxyNodeCard({
                            node: filterProxyNodes(this.groups[groupIndex], this.query)[row * this.nodeColumnCount() + offset],
                            selected: this.selectedNode(this.groups[groupIndex]) === node.name,
                            canSelect: this.groups[groupIndex].selectable,
                            testing: this.isNodeTesting(this.groups[groupIndex].name, node.name),
                            canTest: !this.previewLoading,
                            onSelect: (): void => { this.selectNode(this.groups[groupIndex], node); },
                            onTest: (): void => { this.testNode(this.groups[groupIndex].name, node.name); }
                          })
                        }.layoutWeight(1)
                      }, (node: ProxyNodeSnapshot): string => proxyNodeRenderKey(node))
                    if (this.nodeColumnCount() === 2 &&
                      row * 2 + 1 >= filterProxyNodes(this.groups[groupIndex], this.query).length) {
                      Blank().layoutWeight(1)
                    }
                  }
                  .width('100%').alignItems(VerticalAlign.Top).padding({ left: 12, right: 12, bottom: 8 })
                }
              }, (node: ProxyNodeSnapshot, row: number): string => `${row}:${proxyNodeRenderKey(node)}`)
            if (this.groups[groupIndex].nodes.length === 0) {
              ListItem() {
                Text('当前代理组暂无节点').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
                  .padding(16).width('100%')
              }
            }
          }
        }
        .borderRadius(28).backgroundColor(this.theme.surface)
      }, (groupIndex: number): string => `${groupIndex}:${this.groups[groupIndex].name}:${this.nodeColumnCount()}`)
    }
    .sticky(StickyStyle.Header).scrollBar(BarState.Off)
    .borderRadius(28).clip(true)
    .contentStartOffset(this.headerInset)
    .contentEndOffset(this.metrics.pagePadding + FLOATING_NAVIGATION_INSET)
    .layoutWeight(1).height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  private pageHeader() {
    Column({ space: this.metrics.sectionGap }) {
      PageHeader({
        title: $r('app.string.nav_proxy'), contentPadding: this.metrics.pagePadding,
        actions: (): void => { this.headerActions(); }
      })
      if (this.searchVisible) {
        Search({ value: this.query, placeholder: '搜索代理组、节点或协议' })
          .height(CONTROL_HEIGHT).fontColor($r('app.color.content_primary'))
          .backgroundColor(this.theme.surface).borderRadius(24)
          .margin({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
          .accessibilityText('搜索代理组、节点或协议')
          .onChange((value: string): void => { this.query = value; })
      }
    }
    .width('100%')
  }

  @Builder
  private scrollContent() {
    if (this.groups.length === 0 || this.groupIndexes(0).length === 0) {
      Stack() {
        EmptyStateBackground({
          icon: $r('app.media.nav_proxy'),
          title: this.previewLoading ? '正在解析活动配置…' :
            (this.groups.length === 0 ? '暂无可用代理组' : '没有匹配的代理'),
          description: this.previewLoading ? '解析完成后会显示节点。' : (this.groups.length === 0 ?
            '在配置页添加并选择一份有效配置后，即可查看节点。' : '尝试其他关键词，或清空搜索。')
        })
      }
      .width('100%').height('100%')
      .padding({ top: this.headerInset, left: this.metrics.pagePadding, right: this.metrics.pagePadding })
    } else {
      Row({ space: this.metrics.cardGap }) {
        this.groupColumn(0)
        if (this.columnCount() === 2) { this.groupColumn(1) }
      }
      .width('100%').height('100%').alignItems(VerticalAlign.Top)
      .padding({ left: this.metrics.pagePadding, right: this.metrics.pagePadding })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }

  build() {
    FadingScrollLayout({
      topInset: $headerInset,
      gap: this.metrics.sectionGap,
      header: (): void => { this.pageHeader(); },
      content: (): void => { this.scrollContent(); }
    })
    .onAreaChange((_old: Area, area: Area): void => { this.updateWidth(area.width); })
  }
}
