import {
  ConnectionSnapshot,
  connectionTitle,
  formatBytes,
  RuntimeStoreSnapshot
} from '../models/RuntimeModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { ResponsiveMetrics, resolveResponsiveMetrics } from '../ui/ResponsiveMetrics';

@Component
export struct ConnectionsPage {
  @State available: boolean = false;
  @State refreshing: boolean = false;
  @State connections: ConnectionSnapshot[] = [];
  @State busyKey: string = '';
  @State query: string = '';
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribe: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribe = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.available = snapshot.available;
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

  private updateWidth(width: Length): void {
    const numericWidth = typeof width === 'number' ? width : (typeof width === 'string' ? Number(width) : 0);
    this.metrics = resolveResponsiveMetrics(Number.isFinite(numericWidth) ? numericWidth : 0);
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

  private formatTime(timestamp: number): string {
    return timestamp > 0 ? new Date(timestamp).toLocaleTimeString() : '--';
  }

  @Builder
  private connectionCard(connection: ConnectionSnapshot) {
    Column({ space: 11 }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(connectionTitle(connection))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(connection.destination)
            .fontSize(12)
            .fontColor($r('app.color.content_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        Button('关闭')
          .type(ButtonType.Normal)
          .fontColor($r('app.color.status_error'))
          .enabled(this.busyKey.length === 0)
          .onClick((): void => {
            this.closeConnection(connection.id);
          })
      }
      .width('100%')
      Row({ space: 12 }) {
        Text(`${connection.network.toUpperCase()} · ${connection.type}`)
          .fontSize(12)
          .fontColor($r('app.color.content_secondary'))
        Text(`开始 ${this.formatTime(connection.start)}`)
          .fontSize(12)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
          .textAlign(TextAlign.End)
      }
      .width('100%')
      Text(connection.chains.length > 0 ? `链路：${connection.chains.join(' → ')}` : '链路：等待 Core 数据')
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(2)
        .width('100%')
      Row() {
        Text(`↑ ${formatBytes(connection.upload)}`)
          .fontSize(13)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
        Text(`↓ ${formatBytes(connection.download)}`)
          .fontSize(13)
          .fontColor($r('app.color.content_secondary'))
      }
      .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width(this.metrics.profileCardWidth)
    .padding(16)
    .margin({ bottom: this.metrics.cardGap })
    .borderRadius(16)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder
  private pageContent() {
    Scroll() {
      Column({ space: this.metrics.sectionGap }) {
        Row({ space: 10 }) {
          Column({ space: 4 }) {
            Text($r('app.string.nav_connections'))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.content_primary'))
            Text(`${this.connections.length} 个活动连接`)
              .fontSize(14)
              .fontColor($r('app.color.content_secondary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        TextInput({ placeholder: '搜索域名、地址、进程或链路', text: this.query })
          .height(48)
          .backgroundColor($r('app.color.card_background'))
          .onChange((value: string): void => {
            this.query = value;
          })

        if (!this.available) {
          Column({ space: 10 }) {
            Text('VPN 尚未连接')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.content_primary'))
            Text('连接后，这里会显示 Mihomo 当前管理的真实 TCP、UDP 与 DNS 连接。')
              .fontSize(14)
              .fontColor($r('app.color.content_secondary'))
              .textAlign(TextAlign.Start)
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding(32)
          .borderRadius(18)
          .backgroundColor($r('app.color.card_background'))
        } else if (this.visibleConnections().length === 0) {
          Text(this.query.length > 0 ? '没有匹配的活动连接' : '当前没有活动连接')
            .fontSize(16)
            .fontColor($r('app.color.content_secondary'))
            .textAlign(TextAlign.Start)
            .width('100%')
            .padding(32)
            .borderRadius(18)
            .backgroundColor($r('app.color.card_background'))
        } else {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.visibleConnections(), (connection: ConnectionSnapshot) => {
              this.connectionCard(connection)
            }, (connection: ConnectionSnapshot): string => connection.id)
          }
          .width('100%')
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
  private floatingCloseAllButton() {
    if (this.connections.length > 0) {
      Button('全部关闭')
        .height(52)
        .padding({ left: 20, right: 20 })
        .fontColor(Color.White)
        .backgroundColor($r('app.color.status_error'))
        .enabled(this.available && !this.refreshing && this.busyKey.length === 0)
        .margin({ right: this.metrics.pagePadding, bottom: this.metrics.pagePadding })
        .zIndex(2)
        .onClick((): void => {
          this.closeAllConnections();
        })
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.pageContent()
      this.floatingCloseAllButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.updateWidth(newValue.width);
    })
  }
}
