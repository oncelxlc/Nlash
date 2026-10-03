import { EmptyStateCard } from '../components/EmptyStateCard';
import { formatLocalTime } from '../utils/DateUtils';
import { formatBytes } from '../utils/RuntimeUtils';
import { RequestRecord, RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { RequestFilter } from '../model/NavigationModels';
import { StatusBadge } from '../components/StatusBadge';
import {
  BUTTON_RADIUS, CONTROL_HEIGHT, CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE
} from '../constants/UiConstants';

const FILTERS: RequestFilter[] = [RequestFilter.ALL, RequestFilter.ACTIVE, RequestFilter.COMPLETED];

@Component
export struct RequestsPage {
  @State requests: RequestRecord[] = [];
  @Link filter: RequestFilter;
  @Link query: string;
  @State expandedId: string = '';
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
  private detailLine(value: string) {
    Text(value)
      .fontSize(CAPTION_FONT_SIZE)
      .fontColor($r('app.color.content_secondary'))
      .width('100%')
      .wordBreak(WordBreak.BREAK_ALL)
  }

  @Builder
  private requestRow(record: RequestRecord) {
    Column({ space: 8 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Column({ space: 6 }) {
            Text(this.title(record))
              .fontSize(BODY_FONT_SIZE)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.content_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
            Text(`${record.network.toUpperCase()} · ${formatLocalTime(record.start)}`)
              .fontSize(CAPTION_FONT_SIZE)
              .fontColor($r('app.color.content_secondary'))
              .width('100%')
            Text(`↑ ${formatBytes(record.upload)}  ↓ ${formatBytes(record.download)}`)
              .fontSize(CAPTION_FONT_SIZE)
              .fontColor($r('app.color.content_secondary'))
              .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          StatusBadge({ text: record.active ? '进行中' : '已完成', active: record.active })
          Image($r('app.media.action_chevron_down'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.content_secondary'))
            .rotate({ angle: this.expandedId === record.id ? 180 : 0 })
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ minHeight: 64 })
      .padding({ top: 12, bottom: 12 })
      .borderRadius(0)
      .backgroundColor(Color.Transparent)
      .accessibilityText(`${this.title(record)}，${this.expandedId === record.id ? '收起' : '展开'}请求详情`)
      .onClick((): void => { this.expandedId = this.expandedId === record.id ? '' : record.id; })
      if (this.expandedId === record.id) {
        Column({ space: 8 }) {
          this.detailLine(`主机：${this.title(record)}`)
          this.detailLine(`地址：${record.destination}`)
          this.detailLine(`规则：${record.rule || '未报告'}${record.rulePayload.length > 0 ? ` / ${record.rulePayload}` : ''}`)
          this.detailLine(`链路：${record.chains.length > 0 ? record.chains.join(' → ') : '直连或未报告'}`)
          this.detailLine(`进程：${record.process || '未报告'}`)
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
      TextInput({ placeholder: '搜索主机、地址、规则或进程', text: this.query })
        .height(CONTROL_HEIGHT)
        .fontSize(BODY_FONT_SIZE)
        .fontColor($r('app.color.content_primary'))
        .placeholderColor($r('app.color.content_secondary'))
        .backgroundColor($r('app.color.card_background'))
        .border({ width: 1, color: $r('app.color.control_border') })
        .borderRadius(BUTTON_RADIUS)
        .accessibilityText('搜索请求记录')
        .onChange((value: string): void => { this.query = value; })
      Row({ space: 8 }) {
        ForEach(FILTERS, (item: RequestFilter) => {
          Button(this.filterLabel(item))
            .type(ButtonType.Normal)
            .height(CONTROL_HEIGHT)
            .layoutWeight(1)
            .fontSize(14)
            .borderRadius(BUTTON_RADIUS)
            .fontColor(this.filter === item ? $r('app.color.nav_selected') : $r('app.color.content_secondary'))
            .backgroundColor(this.filter === item ? $r('app.color.nav_selected_background') : Color.Transparent)
            .accessibilitySelected(this.filter === item)
            .onClick((): void => { this.filter = item; })
        }, (item: RequestFilter): string => item)
      }
      .width('100%')
      Row() {
        Text(`${this.visibleRequests().length} 条记录`)
          .fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary'))
          .layoutWeight(1)
        Button('清空记录')
          .type(ButtonType.Normal)
          .height(CONTROL_HEIGHT)
          .borderRadius(BUTTON_RADIUS)
          .fontSize(14)
          .fontColor($r('app.color.status_error'))
          .backgroundColor(Color.Transparent)
          .enabled(this.requests.length > 0)
          .onClick((): void => {
            runtimeStore.clearRequests();
            this.expandedId = '';
            feedbackService.success('请求记录已清空');
          })
      }
      .width('100%')
      List() {
        if (this.visibleRequests().length === 0) {
          ListItem() {
            EmptyStateCard({
              title: this.requests.length === 0 ? '暂无请求记录' : '没有匹配的请求',
              description: this.requests.length === 0 ?
                '产生网络连接后，这里会保留最多 200 条本次会话记录。' : '尝试其他关键词，或切换为全部状态。'
            })
          }
        } else {
          ForEach(this.visibleRequests(), (record: RequestRecord) => {
            ListItem() { this.requestRow(record) }
          }, (record: RequestRecord): string => record.id)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .borderRadius(CARD_RADIUS)
      .clip(true)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .layoutWeight(1)
  }
}
