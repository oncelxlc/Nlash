import {
  ProxyDelayOperationSnapshot,
  ProxyGroupSnapshot,
  ProxyNodeSnapshot,
  ProxySelection,
  ProxySnapshotSource,
  RuntimeStoreSnapshot
} from '../model/RuntimeModels';
import { proxyDelayLabel, proxyNodeRenderKey, visibleProxyGroups } from '../utils/RuntimeUtils';
import { AppSettings, SettingsStoreSnapshot } from '../model/SettingsModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveResponsiveMetrics, resolveContentWidth } from '../utils/ResponsiveUtils';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET,
  CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE
} from '../constants/UiConstants';
import { PageHeader } from '../components/PageHeader';
import { EmptyStateBackground } from '../components/EmptyStateBackground';
import { SingleChoiceControl } from '../components/SingleChoiceControl';
import { StatusBadge } from '../components/StatusBadge';

@Component
export struct ProxyPage {
  @Prop forceExpanded: boolean = false;
  @State coreAvailable: boolean = false;
  @State selecting: boolean = false;
  @State previewLoading: boolean = false;
  @State groups: ProxyGroupSnapshot[] = [];
  @State selections: ProxySelection[] = [];
  @State source: ProxySnapshotSource = ProxySnapshotSource.NONE;
  @State selectedGroup: string = '';
  @State delayOperations: ProxyDelayOperationSnapshot[] = [];
  @State settings: AppSettings = settingsStore.getSnapshot().settings;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribeRuntime: (() => void) | undefined = undefined;
  private unsubscribeSettings: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.coreAvailable = snapshot.coreAvailable;
      this.previewLoading = snapshot.previewLoading;
      this.groups = visibleProxyGroups(snapshot.proxies, snapshot.proxyMode);
      this.selections = snapshot.proxySelections;
      this.source = snapshot.proxySource;
      this.selectedGroup = snapshot.selectedProxyGroup;
      this.delayOperations = snapshot.delayOperations;
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

  private isDirectNodeTesting(node: ProxyNodeSnapshot): boolean {
    const groupName = this.currentGroup()?.name ?? '';
    return this.delayOperations.some((operation: ProxyDelayOperationSnapshot): boolean =>
      operation.group === groupName && operation.proxy === node.name);
  }

  private isGroupTesting(): boolean {
    const groupName = this.currentGroup()?.name ?? '';
    return this.delayOperations.some((operation: ProxyDelayOperationSnapshot): boolean =>
      operation.group === groupName && operation.proxy.length === 0);
  }

  private delayColor(node: ProxyNodeSnapshot, testing: boolean): ResourceColor {
    if (testing || !node.tested) {
      return $r('app.color.content_secondary');
    }
    return node.alive ? $r('app.color.status_success') : $r('app.color.status_error');
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
  private nodeCard(node: ProxyNodeSnapshot) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 4 }) {
          Row({ space: 4 }) {
            Text(node.name)
              .fontSize(BODY_FONT_SIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.content_primary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (this.isNodeSelected(node)) {
              Image($r('app.media.action_check'))
                .width(16).height(16).fillColor($r('app.color.nav_selected'))
            }
          }
          .width('100%')
          Text(`${node.type} · ${node.udp ? 'UDP / TCP' : 'TCP'}`)
            .fontSize(CAPTION_FONT_SIZE)
            .fontColor($r('app.color.content_secondary'))
            .width('100%')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .constraintSize({ minHeight: 56 })
      .padding(0)
      .borderRadius(0)
      .backgroundColor(Color.Transparent)
      .enabled(this.currentGroup()?.selectable === true && !this.selecting)
      .accessibilityText(`${node.name}${this.isNodeSelected(node) ? '，已选择' : ''}`)
      .accessibilitySelected(this.isNodeSelected(node))
      .onClick((): void => { this.selectNode(node); })
      Text(proxyDelayLabel(node, this.isNodeTesting(node)))
        .constraintSize({ minWidth: CONTROL_HEIGHT, minHeight: CONTROL_HEIGHT })
        .textAlign(TextAlign.End)
        .fontSize(CAPTION_FONT_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.delayColor(node, this.isNodeTesting(node)))
        .focusable(true)
        .accessibilityRole(AccessibilityRoleType.BUTTON)
        .stateStyles({ pressed: { .opacity(0.6) } })
        .enabled(!this.isNodeTesting(node) && !this.previewLoading)
        .accessibilityText(`测试 ${node.name} 延迟，${proxyDelayLabel(node, this.isNodeTesting(node))}`)
        .onClick((): void => { this.testNode(node); })
    }
    .width('100%')
    .padding(8)
    .borderRadius(CARD_RADIUS)
    .border({ width: 1, color: this.isNodeSelected(node) ?
      $r('app.color.nav_selected') : $r('app.color.nav_divider') })
    .backgroundColor(this.isNodeSelected(node) ?
      $r('app.color.nav_selected_background') : $r('app.color.card_background'))
  }

  @Builder
  private groupTabs() {
    SingleChoiceControl({
      labels: this.groups.map((group: ProxyGroupSnapshot): string => group.name),
      selectedIndex: this.groups.findIndex((group: ProxyGroupSnapshot): boolean => group.name === this.selectedGroup),
      scrollable: true,
      accessibilityLabel: '代理组',
      onChange: (index: number): void => {
        const group = this.groups[index];
        if (group !== undefined) { this.selectGroup(group.name); }
      }
    })
  }

  @Builder
  private testGroupButton() {
    Button({ type: ButtonType.Normal }) {
      if (this.isGroupTesting()) {
        LoadingProgress().width(20).height(20).color($r('app.color.nav_selected'))
      } else {
        Image($r('app.media.action_refresh')).width(20).height(20).fillColor($r('app.color.nav_selected'))
      }
    }
    .width(CONTROL_HEIGHT).height(CONTROL_HEIGHT)
    .padding(0).borderRadius(BUTTON_RADIUS)
    .backgroundColor($r('app.color.nav_selected_background'))
    .enabled(!this.isGroupTesting() && !this.previewLoading && this.currentGroup() !== undefined)
    .accessibilityText(this.isGroupTesting() ? '当前代理组正在测速' : `测试代理组 ${this.selectedGroup} 的节点延迟`)
    .onClick((): void => { this.testCurrentGroup(); })
  }

  @Builder
  private mainContent() {
    Column({ space: 16 }) {
      PageHeader({
        title: $r('app.string.nav_proxy'),
        subtitle: this.source === ProxySnapshotSource.RUNTIME ? '选择流量出口，查看节点延迟' : '连接前也可预选节点与测试延迟',
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
      if (this.groups.length === 0) {
        Stack() {
          EmptyStateBackground({
            icon: $r('app.media.nav_proxy'),
            title: this.previewLoading ? '正在解析活动配置…' : '暂无可用代理组',
            description: this.previewLoading ? '解析完成后会显示节点。' : '在配置页添加并选择一份有效配置后，即可查看节点。'
          })
        }
        .width('100%').layoutWeight(1)
      } else {
        this.groupTabs()
        Text(`${this.selectedGroup} · ${this.currentGroup()?.nodes.length ?? 0} 个节点`)
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary'))
          .width('100%')
        Stack() {
          if ((this.currentGroup()?.nodes.length ?? 0) === 0) {
            EmptyStateBackground({
              icon: $r('app.media.nav_proxy'), title: '当前代理组暂无节点', description: '尝试其他代理组，或更新活动配置。'
            })
          }
          Grid() {
            ForEach(this.currentGroup()?.nodes ?? [], (node: ProxyNodeSnapshot) => {
              GridItem() { this.nodeCard(node) }
            }, (node: ProxyNodeSnapshot): string => proxyNodeRenderKey(node))
          }
          .columnsTemplate(this.metrics.proxyColumns)
          .columnsGap(this.metrics.cardGap)
          .rowsGap(this.metrics.cardGap)
          .width('100%').height('100%')
          .contentEndOffset(this.metrics.pagePadding + FLOATING_NAVIGATION_INSET)
          .scrollBar(BarState.Auto)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
        .width('100%').layoutWeight(1)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .height('100%')
    .padding({
      top: this.metrics.pagePadding, left: this.metrics.pagePadding, right: this.metrics.pagePadding
    })
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
