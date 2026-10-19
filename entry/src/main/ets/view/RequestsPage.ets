import { EmptyStateBackground } from '../components/EmptyStateBackground';
import { SecondaryPageHeader } from '../components/SecondaryPageHeader';
import { HeaderIconButton } from '../components/HeaderIconButton';
import { ConnectionRoute } from '../components/ConnectionRoute';
import { SingleChoiceControl } from '../components/SingleChoiceControl';
import { RequestRecord, RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { RequestFilter } from '../model/NavigationModels';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { formatBytes } from '../utils/RuntimeUtils';
import { formatRecordTime, requestEndpoint } from '../utils/ActivityUtils';
import { revealTransition, selectionAnimation } from '../utils/AnimationUtils';
import { CONTROL_HEIGHT, DETAIL_CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE } from '../constants/UiConstants';

const FILTERS: RequestFilter[] = [RequestFilter.ALL, RequestFilter.ACTIVE, RequestFilter.COMPLETED];

/** 会话历史按时间倒序展示；搜索展开后保留已有状态筛选与清空操作。 */
interface RequestCardData { record: RequestRecord; }

@Component
export struct RequestsPage {
  @Prop contentPadding: number = 16;
  @Link filter: RequestFilter;
  @Link query: string;
  onBack: () => void = (): void => {};
  @State requests: RequestRecord[] = [];
  @State recordsById: Map<string, RequestRecord> = new Map<string, RequestRecord>();
  @State searching: boolean = false;
  @State expandedId: string = '';
  private unsubscribe: (() => void) | undefined;

  aboutToAppear(): void {
    this.searching = this.query.length > 0 || this.filter !== RequestFilter.ALL;
    this.unsubscribe = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      const records = new Map<string, RequestRecord>();
      snapshot.requests.forEach((item: RequestRecord): void => { records.set(item.id, item); });
      this.recordsById = records;
      this.requests = snapshot.requests;
    });
  }

  aboutToDisappear(): void { this.unsubscribe?.(); }

  private visibleRequests(): RequestRecord[] {
    const keyword = this.query.trim().toLowerCase();
    return this.requests.filter((record: RequestRecord): boolean => {
      if (this.filter === RequestFilter.ACTIVE && !record.active) { return false; }
      if (this.filter === RequestFilter.COMPLETED && record.active) { return false; }
      return [record.host, record.destination, record.rule, record.rulePayload, record.process, record.chains.join(' ')]
        .join(' ').toLowerCase().includes(keyword);
    });
  }

  private async clearRecords(): Promise<void> {
    const result = await this.getUIContext().getPromptAction().showDialog({
      title: '清空最近请求？', message: '仅清空本次会话的记录，不会关闭活动连接。',
      buttons: [{ text: '取消', color: $r('app.color.content_secondary') },
        { text: '清空', color: $r('app.color.status_error') }]
    });
    if (result.index === 1) {
      this.getUIContext().animateTo(selectionAnimation(), (): void => {
        runtimeStore.clearRequests();
        this.expandedId = '';
      });
      feedbackService.success('请求记录已清空');
    }
  }

  @Builder
  private actions() {
    HeaderIconButton({ label: this.searching ? '收起搜索与筛选' : '搜索与筛选最近请求',
      onActivate: (): void => { this.searching = !this.searching; } })
  }

  @Builder
  private searchControls() {
    Column({ space: 12 }) {
      TextInput({ placeholder: '搜索主机、地址、规则、进程或链路', text: this.query })
        .id('request-search').height(CONTROL_HEIGHT).fontSize(BODY_FONT_SIZE)
        .fontColor($r('app.color.content_primary')).placeholderColor($r('app.color.content_secondary'))
        .backgroundColor($r('app.color.card_background')).borderRadius(24)
        .accessibilityText('搜索最近请求').onChange((value: string): void => { this.query = value; })
      SingleChoiceControl({ labels: ['全部', '进行中', '已完成'],
        selectedIndex: FILTERS.indexOf(this.filter), accessibilityLabel: '请求状态筛选',
        onChange: (index: number): void => { this.filter = FILTERS[index]; } })
      Row() {
        Text(`${this.visibleRequests().length} 条记录`).fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary')).layoutWeight(1)
        Button('清空记录').height(CONTROL_HEIGHT).fontSize(14)
          .fontColor($r('app.color.status_error')).backgroundColor(Color.Transparent)
          .enabled(this.requests.length > 0).onClick((): void => {
            this.clearRecords().catch((): void => { feedbackService.error('无法完成清空操作，请重试'); });
          })
      }.width('100%')
    }
    .padding({ left: this.contentPadding, right: this.contentPadding, bottom: 12 })
    .transition(revealTransition())
  }

  @Builder
  private requestCard(data: RequestCardData) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 10 }) {
        Row({ space: 10 }) {
          Text(formatRecordTime(data.record.start)).fontSize(CAPTION_FONT_SIZE)
            .fontColor($r('app.color.content_secondary')).layoutWeight(1)
          Text(data.record.network.toUpperCase()).fontSize(CAPTION_FONT_SIZE).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_secondary'))
        }.width('100%')
        Text(requestEndpoint(data.record.host, data.record.destination)).fontSize(18).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary')).width('100%').wordBreak(WordBreak.BREAK_ALL)
        if (data.record.host.length > 0) {
          Text(data.record.destination).fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary'))
            .width('100%').wordBreak(WordBreak.BREAK_ALL)
        }
        ConnectionRoute({ rule: data.record.rule, payload: data.record.rulePayload, chains: data.record.chains.slice().reverse() })
        Text(data.record.process || data.record.source || '来源未报告').fontSize(CAPTION_FONT_SIZE)
          .fontColor($r('app.color.content_secondary')).width('100%').wordBreak(WordBreak.BREAK_ALL)
        if (this.expandedId === data.record.id) {
          Column({ space: 8 }) {
            Divider().color($r('app.color.nav_divider'))
            Text(`${data.record.active ? '进行中' : '已完成'} · ↑ ${formatBytes(data.record.upload)}  ↓ ${formatBytes(data.record.download)}`)
              .fontSize(CAPTION_FONT_SIZE).fontColor($r('app.color.content_secondary')).width('100%')
            if (data.record.end > 0) {
              Text(`结束于 ${formatRecordTime(data.record.end)}`).fontSize(CAPTION_FONT_SIZE)
                .fontColor($r('app.color.content_secondary')).width('100%')
            }
          }.width('100%').transition(revealTransition())
        }
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(20).borderRadius(DETAIL_CARD_RADIUS)
    .backgroundColor($r('app.color.card_background'))
    .accessibilityText(`${requestEndpoint(data.record.host, data.record.destination)}，${data.record.active ? '进行中' : '已完成'}，` +
      `${this.expandedId === data.record.id ? '收起' : '展开'}请求详情`)
    .onClick((): void => { this.expandedId = this.expandedId === data.record.id ? '' : data.record.id; })
  }

  build() {
    Column() {
      SecondaryPageHeader({ title: '最近请求', contentPadding: this.contentPadding,
        onBack: this.onBack, actions: (): void => { this.actions(); } })
      if (this.searching) { this.searchControls() }
      Stack() {
        if (this.visibleRequests().length === 0) {
          EmptyStateBackground({ icon: $r('app.media.nav_requests'),
            title: this.requests.length === 0 ? '暂无请求记录' : '没有匹配的请求',
            description: this.requests.length === 0 ? '产生网络连接后，这里会保留最近 200 条会话记录。' :
              '尝试其他关键词，或切换为全部状态。' })
        }
        List({ space: 12 }) {
          ForEach(this.visibleRequests(), (record: RequestRecord) => {
            ListItem() { this.requestCard({ record: this.recordsById.get(record.id) ?? record }) }.transition(revealTransition())
          }, (record: RequestRecord): string => record.id)
        }
        .width('100%').height('100%').contentStartOffset(12).contentEndOffset(32).scrollBar(BarState.Off)
      }.width('100%').layoutWeight(1).padding({ left: this.contentPadding, right: this.contentPadding })
    }.width('100%').height('100%').backgroundColor($r('app.color.app_background'))
  }
}
