import { EmptyStateCard } from '../components/EmptyStateCard';
import { formatLocalTime } from '../utils/DateUtils';
import { ConnectionSnapshot, RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { connectionTitle, formatBytes } from '../utils/RuntimeUtils';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, FLOATING_NAVIGATION_INSET, CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE
} from '../constants/UiConstants';

@Component
export struct ConnectionsPage {
  @State available: boolean = false;
  @State refreshing: boolean = false;
  @State connections: ConnectionSnapshot[] = [];
  @State busyKey: string = '';
  @Link query: string;
  @State expandedId: string = '';
  private unsubscribe: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribe = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.available = snapshot.coreAvailable;
      this.refreshing = snapshot.refreshing;
      this.connections = snapshot.connections;
      this.busyKey = snapshot.busyKey;
    });
    runtimeStore.refresh();
  }

  private async closeConnection(id: string): Promise<void> {
    try {
      await runtimeStore.closeConnection(id);
      feedbackService.success('连接已关闭');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private async closeAllConnections(): Promise<void> {
    try {
      await runtimeStore.closeAllConnections();
      feedbackService.success('全部连接已关闭');
    } catch (error) {
      feedbackService.error(this.errorMessage(error));
    }
  }

  private errorMessage(error: Object): string {
    const exception = error as Error;
    return typeof exception.message === 'string' && exception.message.length > 0 ?
      exception.message : '连接操作失败';
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  private visibleConnections(): ConnectionSnapshot[] {
    const keyword = this.query.trim().toLowerCase();
    if (keyword.length === 0) {
      return this.connections;
    }
    return this.connections.filter((connection: ConnectionSnapshot): boolean => {
      return connection.host.toLowerCase().includes(keyword) ||
        connection.destination.toLowerCase().includes(keyword) ||
        connection.process.toLowerCase().includes(keyword) ||
        connection.chains.join(' ').toLowerCase().includes(keyword);
    });
  }

  @Builder
  private detailLine(value: string) {
    Text(value)
      .fontSize(CAPTION_FONT_SIZE)
      .fontColor($r('app.color.content_secondary'))
      .width('100%')
      .wordBreak(WordBreak.BREAK_ALL)
  }

  @Builder
  private connectionRow(connection: ConnectionSnapshot) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            Column({ space: 6 }) {
              Text(connectionTitle(connection))
                .fontSize(BODY_FONT_SIZE)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.content_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              Text(`${connection.network.toUpperCase()} · ↑ ${formatBytes(connection.upload)}  ↓ ${formatBytes(connection.download)}`)
                .fontSize(CAPTION_FONT_SIZE)
                .fontColor($r('app.color.content_secondary'))
                .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Image($r('app.media.action_chevron_down'))
              .width(16)
              .height(16)
              .fillColor($r('app.color.content_secondary'))
              .rotate({ angle: this.expandedId === connection.id ? 180 : 0 })
          }
        }
        .layoutWeight(1)
        .constraintSize({ minHeight: 72 })
        .padding({ top: 12, bottom: 12 })
        .borderRadius(0)
        .backgroundColor(Color.Transparent)
        .accessibilityText(`${connectionTitle(connection)}，${this.expandedId === connection.id ? '收起' : '展开'}连接详情`)
        .onClick((): void => { this.expandedId = this.expandedId === connection.id ? '' : connection.id; })
        Button('关闭')
          .type(ButtonType.Normal)
          .height(CONTROL_HEIGHT)
          .fontSize(14)
          .borderRadius(BUTTON_RADIUS)
          .fontColor($r('app.color.status_error'))
          .backgroundColor($r('app.color.status_error_surface'))
          .enabled(this.available && this.busyKey.length === 0)
          .accessibilityText(`关闭 ${connectionTitle(connection)} 的连接`)
          .onClick((): void => { this.closeConnection(connection.id); })
      }
      .width('100%')
      if (this.expandedId === connection.id) {
        Column({ space: 8 }) {
          this.detailLine(`主机：${connectionTitle(connection)}`)
          this.detailLine(`地址：${connection.destination}`)
          this.detailLine(`类型：${connection.network.toUpperCase()} · ${connection.type}`)
          this.detailLine(`开始：${formatLocalTime(connection.start)}`)
          this.detailLine(`链路：${connection.chains.length > 0 ? connection.chains.join(' → ') : '等待 Core 数据'}`)
          this.detailLine(`规则：${connection.rule || '未报告'}${connection.rulePayload.length > 0 ? ` / ${connection.rulePayload}` : ''}`)
          this.detailLine(`进程：${connection.process || '未报告'}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: 16 })
      }
      Divider().color($r('app.color.nav_divider'))
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
  }

  build() {
    Column({ space: 12 }) {
      TextInput({ placeholder: '搜索主机、地址、进程或链路', text: this.query })
        .height(CONTROL_HEIGHT)
        .fontSize(BODY_FONT_SIZE)
        .fontColor($r('app.color.content_primary'))
        .placeholderColor($r('app.color.content_secondary'))
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1, color: $r('app.color.control_border') })
        .borderRadius(BUTTON_RADIUS)
        .accessibilityText('搜索实时连接')
        .onChange((value: string): void => { this.query = value; })
      Row({ space: 8 }) {
        if (this.refreshing) {
          LoadingProgress().width(16).height(16).color($r('app.color.nav_selected'))
        }
        Text(`${this.visibleConnections().length} 个活动连接`)
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
        Button(this.busyKey.length > 0 ? '处理中…' : '全部关闭')
          .type(ButtonType.Normal)
          .height(CONTROL_HEIGHT)
          .borderRadius(BUTTON_RADIUS)
          .fontSize(14)
          .fontColor($r('app.color.status_error'))
          .backgroundColor(Color.Transparent)
          .enabled(this.available && !this.refreshing && this.busyKey.length === 0 && this.connections.length > 0)
          .onClick((): void => { this.closeAllConnections(); })
      }
      .width('100%')
      List() {
        if (!this.available) {
          ListItem() {
            EmptyStateCard({ title: '运行数据暂不可用', description: 'Core 就绪后，这里会显示当前管理的 TCP、UDP 与 DNS 连接。' })
          }
        } else if (this.visibleConnections().length === 0) {
          ListItem() {
            EmptyStateCard({
              title: this.query.trim().length > 0 ? '没有匹配的连接' : '当前没有活动连接',
              description: this.query.trim().length > 0 ? '尝试其他关键词。' : '有新的网络连接时会自动出现在这里。'
            })
          }
        } else {
          ForEach(this.visibleConnections(), (connection: ConnectionSnapshot) => {
            ListItem() { this.connectionRow(connection) }
          }, (connection: ConnectionSnapshot): string => connection.id)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius(CARD_RADIUS)
      .contentEndOffset(FLOATING_NAVIGATION_INSET + 16)
      .clip(true)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .layoutWeight(1)
  }
}
