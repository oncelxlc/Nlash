import { EmptyStateCard } from '../components/EmptyStateCard';
import { formatLocalTime } from '../utils/DateUtils';
import { formatBytes } from '../utils/RuntimeUtils';
import { RequestRecord, RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { ResponsiveMetrics } from '../model/ResponsiveModels';
import { resolveResponsiveMetrics, resolveContentWidth } from '../utils/ResponsiveUtils';
import { BUTTON_RADIUS, FLOATING_NAVIGATION_INSET } from '../constants/UiConstants';

enum RequestFilter {
  ALL = 'ALL',
  ACTIVE = 'ACTIVE',
  COMPLETED = 'COMPLETED'
}

const FILTERS: RequestFilter[] = [RequestFilter.ALL, RequestFilter.ACTIVE, RequestFilter.COMPLETED];

@Component
export struct RequestsPage {
  @State requests: RequestRecord[] = [];
  @State filter: RequestFilter = RequestFilter.ALL;
  @State query: string = '';
  @State metrics: ResponsiveMetrics = resolveResponsiveMetrics(0);
  private unsubscribe: (() => void) | undefined = undefined;

  aboutToAppear(): void {
    this.unsubscribe = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.requests = snapshot.requests;
    });
  }

  aboutToDisappear(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
  }

  private updateWidth(width: Length): void {
    this.metrics = resolveResponsiveMetrics(resolveContentWidth(width));
  }

  private filterLabel(filter: RequestFilter): string {
    if (filter === RequestFilter.ACTIVE) {
      return '进行中';
    }
    if (filter === RequestFilter.COMPLETED) {
      return '已完成';
    }
    return '全部';
  }

  private visibleRequests(): RequestRecord[] {
    const keyword = this.query.trim().toLowerCase();
    return this.requests.filter((record: RequestRecord): boolean => {
      if (this.filter === RequestFilter.ACTIVE && !record.active) {
        return false;
      }
      if (this.filter === RequestFilter.COMPLETED && record.active) {
        return false;
      }
      if (keyword.length === 0) {
        return true;
      }
      return record.host.toLowerCase().includes(keyword) || record.destination.toLowerCase().includes(keyword) ||
        record.rule.toLowerCase().includes(keyword) || record.process.toLowerCase().includes(keyword);
    });
  }

  private title(record: RequestRecord): string {
    return record.host.length > 0 ? record.host : record.destination;
  }

  @Builder
  private requestCard(record: RequestRecord) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.title(record))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(record.active ? '进行中' : '已完成')
          .fontSize(12)
          .fontColor(record.active ? $r('app.color.status_success') : $r('app.color.content_secondary'))
      }
      .width('100%')
      Text(record.destination)
        .fontSize(12)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
      Text(record.rule.length > 0 ?
        `规则：${record.rule}${record.rulePayload.length > 0 ? ` / ${record.rulePayload}` : ''}` : '规则：未报告')
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(2)
        .width('100%')
      Text(record.chains.length > 0 ? `链路：${record.chains.join(' → ')}` : '链路：直连或未报告')
        .fontSize(13)
        .fontColor($r('app.color.content_secondary'))
        .maxLines(2)
        .width('100%')
      Row() {
        Text(`${record.network.toUpperCase()} · ${formatLocalTime(record.start)}`)
          .fontSize(12)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
        Text(`↑ ${formatBytes(record.upload)}  ↓ ${formatBytes(record.download)}`)
          .fontSize(12)
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
            Text($r('app.string.nav_requests'))
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.content_primary'))
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')

        TextInput({ placeholder: '搜索主机、地址、规则或进程', text: this.query })
          .height(48)
          .backgroundColor($r('app.color.card_background'))
          .onChange((value: string): void => {
            this.query = value;
          })

        Row({ space: 8 }) {
          ForEach(FILTERS, (item: RequestFilter) => {
            Button(this.filterLabel(item))
              .type(ButtonType.Normal)
              .borderRadius(BUTTON_RADIUS)
              .fontColor(this.filter === item ? Color.White : $r('app.color.content_primary'))
              .backgroundColor(this.filter === item ? $r('app.color.nav_selected') : $r('app.color.card_background'))
              .onClick((): void => {
                this.filter = item;
              })
          }, (item: RequestFilter): string => item)
        }
        .width('100%')

        if (this.visibleRequests().length === 0) {
          EmptyStateCard({
            title: '暂无请求记录',
            description: '建立 VPN 并产生网络连接后，此处会保留最多 200 条会话内记录。'
          })
        } else {
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.visibleRequests(), (record: RequestRecord) => {
              this.requestCard(record)
            }, (record: RequestRecord): string => `${record.id}:${record.active}`)
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
        bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private floatingClearButton() {
    if (this.requests.length > 0) {
      Button('清空记录')
        .type(ButtonType.Normal)
        .borderRadius(BUTTON_RADIUS)
        .height(52)
        .padding({ left: 20, right: 20 })
        .fontColor(Color.White)
        .backgroundColor($r('app.color.nav_selected'))
        .margin({
          right: this.metrics.pagePadding,
          bottom: this.metrics.pagePadding + FLOATING_NAVIGATION_INSET
        })
        .zIndex(2)
        .onClick((): void => {
          runtimeStore.clearRequests();
          feedbackService.success('请求记录已清空');
        })
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.pageContent()
      this.floatingClearButton()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.app_background'))
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.updateWidth(newValue.width);
    })
  }
}
