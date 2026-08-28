import {
  ProxyGroupSnapshot,
  ProxyNodeSnapshot,
  ProxySelection,
  ProxySnapshotSource,
  RuntimeStoreSnapshot
} from '../models/RuntimeModels';
import { AppSettings, SettingsStoreSnapshot } from '../models/SettingsModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { settingsStore } from '../stores/SettingsStore';
import { ResponsiveMetrics, resolveResponsiveMetrics } from '../ui/ResponsiveMetrics';
import { BUTTON_RADIUS } from '../ui/UiConstants';

@Component
export struct ProxyPage {
  @Prop forceExpanded: boolean = false;
  @State available: boolean = false;
  @State refreshing: boolean = false;
  @State previewLoading: boolean = false;
  @State groups: ProxyGroupSnapshot[] = [];
  @State selections: ProxySelection[] = [];
  @State source: ProxySnapshotSource = ProxySnapshotSource.NONE;
  @State selectedGroup: string = '';
  @State busyKey: string = '';
  @State settings: AppSettings = settingsStore.getSnapshot().settings;
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribeRuntime: (() => void) | undefined = undefined;
  private unsubscribeSettings: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.available = snapshot.available;
      this.refreshing = snapshot.refreshing;
      this.previewLoading = snapshot.previewLoading;
      this.groups = snapshot.proxies.filter((group: ProxyGroupSnapshot): boolean => !group.hidden);
      this.selections = snapshot.proxySelections;
      this.source = snapshot.proxySource;
      this.busyKey = snapshot.busyKey;
      if (this.groups.length > 0 && !this.groups.some((group: ProxyGroupSnapshot): boolean =>
        group.name === this.selectedGroup)) {
        this.selectedGroup = this.groups[0].name;
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
    const numericWidth = typeof width === 'number' ? width : (typeof width === 'string' ? Number(width) : 0);
    this.metrics = resolveResponsiveMetrics(Number.isFinite(numericWidth) ? numericWidth : 0, this.forceExpanded);
  }

  private currentGroup(): ProxyGroupSnapshot | undefined {
    return this.groups.find((group: ProxyGroupSnapshot): boolean => group.name === this.selectedGroup);
  }

  private preselectedNode(group: string): string {
    return this.selections.find((selection: ProxySelection): boolean => selection.group === group)?.proxy ?? '';
  }

  private statusLabel(node: ProxyNodeSnapshot): string {
    const group = this.currentGroup();
    if (this.available && group?.selected === node.name) {
      return '当前';
    }
    return this.preselectedNode(group?.name ?? '') === node.name ? '预选' : '';
  }

  private delayLabel(node: ProxyNodeSnapshot): string {
    if (!node.tested) {
      return '未测试';
    }
    return node.alive && node.delay > 0 ? `${node.delay} ms` : '不可用';
  }

  private delayColor(node: ProxyNodeSnapshot): ResourceColor {
    if (!node.tested) {
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
        const delay = await runtimeStore.testDelay(group.name, node.name, this.settings.delayTestUrl);
        if (delay > 0) {
          feedbackService.success(`${node.name} 延迟 ${delay} ms`);
        } else {
          feedbackService.warning(`${node.name} 当前不可用`);
        }
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
      feedbackService.success(`${group.name} 延迟测试完成`);
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
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Text(node.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.statusLabel(node).length > 0) {
            Text(this.statusLabel(node))
              .fontSize(11)
              .fontColor($r('app.color.status_success'))
          }
        }
        .width('100%')
        Row({ space: 8 }) {
          Text(`${node.type} · ${node.udp ? 'UDP' : 'TCP'}`)
            .fontSize(11)
            .fontColor($r('app.color.content_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text(this.delayLabel(node))
            .fontSize(11)
            .fontColor(this.delayColor(node))
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .padding({ right: 44 })
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding(14)
      .border({ width: this.statusLabel(node).length > 0 ? 1 : 0,
        color: $r('app.color.status_success') })
      .borderRadius(14)
      .backgroundColor($r('app.color.card_background'))
      .onClick((): void => { this.selectNode(node); })
      Button('⚡')
        .type(ButtonType.Normal)
        .borderRadius(BUTTON_RADIUS)
        .fontSize(14)
        .width(38)
        .height(30)
        .zIndex(1)
        .margin({ right: 14, bottom: 14 })
        .enabled(this.busyKey.length === 0)
        .onClick((): void => { this.testNode(node); })
    }
    .width(this.metrics.proxyCardWidth)
    .margin({ bottom: this.metrics.cardGap })
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
            .fontColor(this.available ? $r('app.color.status_success') : $r('app.color.content_secondary'))
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
                  .onClick((): void => { this.selectedGroup = group.name; })
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
            Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
              ForEach(this.currentGroup()?.nodes ?? [], (node: ProxyNodeSnapshot) => {
                this.nodeCard(node)
              }, (node: ProxyNodeSnapshot): string => node.name)
            }
            .width('100%')
          }
        }

      }
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        top: this.metrics.pagePadding,
        left: this.metrics.pagePadding,
        right: this.metrics.pagePadding,
        bottom: this.metrics.pagePadding + 80
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private floatingDelayButton() {
    if (this.currentGroup() !== undefined) {
      Button(this.busyKey.length > 0 ? '测速中…' : '⚡ 测试当前组')
        .type(ButtonType.Normal)
        .borderRadius(BUTTON_RADIUS)
        .height(52)
        .padding({ left: 20, right: 20 })
        .backgroundColor($r('app.color.nav_selected'))
        .fontColor(Color.White)
        .enabled(this.busyKey.length === 0 && !this.refreshing && !this.previewLoading)
        .accessibilityText('测试当前代理组延迟')
        .margin({ right: this.metrics.pagePadding, bottom: this.metrics.pagePadding })
        .zIndex(2)
        .onClick((): void => {
          this.testCurrentGroup();
        })
    }
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
