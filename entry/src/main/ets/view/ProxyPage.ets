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
import { BUTTON_RADIUS, FLOATING_NAVIGATION_INSET } from '../constants/UiConstants';
import { LengthMetrics, LengthUnit } from '@kit.ArkUI';

@Component
export struct ProxyPage {
  @Prop forceExpanded: boolean = false;
  @State coreAvailable: boolean = false;
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
    if (group !== undefined && group.selectable) {
      try {
        await runtimeStore.selectProxy(group.name, node.name);
        feedbackService.success(`已选择 ${node.name}`);
      } catch (error) {
        feedbackService.error(this.errorMessage(error));
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

  private currentGroupNodesLength(): number {
    return this.currentGroup()?.nodes.length ?? 0;
  }

  @Builder
  private nodeCard(node: ProxyNodeSnapshot) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: 0 }) {
        Row() {
          Text(node.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        Row({ space: 4 }) {
          Text(`${node.type} ${node.udp ? 'UDP' : 'TCP'}`)
            .fontSize(11)
            .fontColor($r('app.color.content_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(proxyDelayLabel(node, this.isNodeTesting(node)))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.delayColor(node, this.isNodeTesting(node)))
            .textAlign(TextAlign.End)
            .accessibilityText(`测试 ${node.name} 延迟`)
            .padding({top: 4,right: 4, bottom: 4, left: 8})
            .margin({right: -4})
            .onTouch((event: TouchEvent): void => {
              event.stopPropagation();
              if (event.type === TouchType.Up && !this.isDirectNodeTesting(node)) {
                this.testNode(node);
              }
            })
            .hitTestBehavior(HitTestMode.Block)
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ top: 12, bottom: 10, left: 12, right: 10 })
      .border({ width: 1,
        color: this.isNodeSelected(node) ? $r('app.color.status_success') : $r('app.color.card_background') })
      .borderRadius(14)
      .backgroundColor($r('app.color.card_background'))
      .onClick((): void => { this.selectNode(node); })
    }
    .width('100%')
  }

  @Builder
  private pageContent() {
    Scroll() {
      Column({ space: this.metrics.sectionGap }) {
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text($r('app.string.nav_proxy'))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.content_primary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Text(this.source === ProxySnapshotSource.RUNTIME ? '运行中' :
            (this.source === ProxySnapshotSource.CONFIG ? '配置预览' : '无配置'))
            .fontSize(12)
            .fontColor(this.coreAvailable ?
              $r('app.color.status_success') : $r('app.color.content_secondary'))
        }
        .width('100%')
        if (this.groups.length === 0) {
          Column({ space: 8 }) {
            Text(this.previewLoading ? '正在解析活动配置…' : '暂无可用代理组')
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.content_primary'))
            Text('请在配置页添加并选择一份有效配置。')
              .fontSize(14)
              .fontColor($r('app.color.content_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(20)
          .borderRadius(16)
          .backgroundColor($r('app.color.card_background'))
        } else {
          Scroll() {
            Row({ space: 8 }) {
              ForEach(this.groups, (group: ProxyGroupSnapshot) => {
                Button(group.name)
                  .type(ButtonType.Normal)
                  .borderRadius(BUTTON_RADIUS)
                  .fontColor(this.selectedGroup === group.name ? Color.White : $r('app.color.content_primary'))
                  .backgroundColor(this.selectedGroup === group.name ?
                    $r('app.color.nav_selected') : $r('app.color.card_background'))
                  .onClick((): void => { this.selectGroup(group.name); })
              }, (group: ProxyGroupSnapshot): string => group.name)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .width('100%')
          if (this.currentGroup() !== undefined) {
            Row() {
              Text(`${this.currentGroup()?.name ?? ''} · ${this.currentGroup()?.nodes.length ?? 0} 个节点`)
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.content_primary'))
                .layoutWeight(1)
              Text(this.currentGroup()?.selectable ? '点击卡片选择' : '只读组')
                .fontSize(12)
                .fontColor($r('app.color.content_secondary'))
            }
            .width('100%')
            Grid(new Scroller(), {
              regularSize: [1, 1],
              irregularIndexes: [this.currentGroupNodesLength()],
              onGetIrregularSizeByIndex: (): [number, number] => [1, this.metrics.proxyColumns.split(' ').length]
            }) {
              ForEach(this.currentGroup()?.nodes ?? [], (node: ProxyNodeSnapshot) => {
                GridItem() {
                  this.nodeCard(node)
                }
              }, (node: ProxyNodeSnapshot): string => proxyNodeRenderKey(node))
              GridItem()
                .height(this.metrics.pagePadding + 130)
                .width('100%')
            }
            .columnsTemplate(this.metrics.proxyColumns)
            .columnsGap(this.metrics.cardGap)
            .rowsGap(this.metrics.cardGap)
            .width('100%')
            .scrollBar(BarState.Off)
          }
        }

      }
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .height('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        top: this.metrics.pagePadding,
        left: this.metrics.pagePadding,
        right: this.metrics.pagePadding,
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private floatingDelayButton() {
    Button(this.isGroupTesting() ? '测速中…' : '⚡ 测试全部')
      .type(ButtonType.Normal)
      .borderRadius(BUTTON_RADIUS)
      .height(52)
      .padding({ left: 20, right: 20 })
      .backgroundColor($r('app.color.nav_selected'))
      .fontColor(Color.White)
      .enabled(!this.isGroupTesting() && !this.previewLoading && this.currentGroup() !== undefined)
      .accessibilityText('测试当前代理组延迟')
      .margin({
        right: this.metrics.pagePadding,
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET - 10
      })
      .zIndex(2)
      .onClick((): void => {
        this.testCurrentGroup();
      })
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.pageContent()
      this.floatingDelayButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_oldValue: Area, newValue: Area): void => { this.updateWidth(newValue.width); })
  }
}
