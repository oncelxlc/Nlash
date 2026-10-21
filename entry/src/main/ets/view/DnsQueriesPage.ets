import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { DnsQueryRecord } from '../model/DiagnosticsModels';
import { RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { diagnosticsService } from '../services/DiagnosticsService';
import { runtimeStore } from '../stores/RuntimeStore';
import { SecondaryPageHeader } from '../components/SecondaryPageHeader';
import { HeaderIconButton } from '../components/HeaderIconButton';
import { EmptyStateBackground } from '../components/EmptyStateBackground';
import { formatRecordTime } from '../utils/ActivityUtils';
import { dnsInitiatorLabel, filterDnsQueries } from '../utils/DiagnosticsUtils';
import { revealTransition } from '../utils/AnimationUtils';
import { CONTROL_HEIGHT, DETAIL_CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE } from '../constants/UiConstants';

@Component
export struct DnsQueriesPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop contentPadding: number = 16;
  onBack: () => void = (): void => {};
  @State records: DnsQueryRecord[] = [];
  @State query: string = '';
  @State searching: boolean = false;
  @State expandedId: string = '';
  @State available: boolean = false;
  @State errorMessage: string = '';
  private active: boolean = false;
  private loading: boolean = false;
  private lastRead: number = 0;
  private generation: number = 0;
  private unsubscribe: (() => void) | undefined;

  aboutToAppear(): void {
    this.active = true;
    this.unsubscribe = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      if (this.available !== snapshot.coreAvailable) { this.generation += 1; }
      this.available = snapshot.coreAvailable;
      if (this.available && Date.now() - this.lastRead >= 2000) { this.loadRecords(); }
    });
  }

  aboutToDisappear(): void { this.active = false; this.unsubscribe?.(); }

  private async loadRecords(): Promise<void> {
    if (this.loading) { return; }
    this.loading = true;
    this.lastRead = Date.now();
    const generation = this.generation;
    try {
      const records = await diagnosticsService.dnsQueries();
      if (this.active && generation === this.generation) {
        this.records = records;
        this.errorMessage = '';
      }
    } catch (error) {
      if (this.active && generation === this.generation) {
        this.errorMessage = (error as Error).message || '读取失败，请返回后重试';
      }
    } finally { this.loading = false; }
  }

  @Builder
  private actions() {
    HeaderIconButton({ label: this.searching ? '收起 DNS 搜索' : '搜索 DNS 查询',
      onActivate: (): void => { this.searching = !this.searching; } })
  }

  @Builder
  private badge(text: string) {
    Text(text).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_primary'))
      .padding({ left: 8, right: 8, top: 3, bottom: 3 }).borderRadius(12)
      .backgroundColor(this.theme.muted).margin({ right: 8, bottom: 4 })
  }

  @Builder
  private queryCard(record: DnsQueryRecord) {
    Button({ type: ButtonType.Normal }) {
      Column({ space: 10 }) {
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          Text(formatRecordTime(record.start)).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor($r('app.color.content_secondary')).margin({ right: 12, bottom: 4 })
          this.badge(record.type)
          Text(`${record.duration} ms`).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
        }.width('100%')
        Text(record.host).fontSize(themeFontSize(18, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.content_primary')).width('100%').wordBreak(WordBreak.BREAK_ALL)
        Text(record.error || (record.answers.length > 0 ? record.answers.join(', ') : '无应答记录'))
          .fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor(record.error ? $r('app.color.status_error') : $r('app.color.content_secondary'))
          .maxLines(this.expandedId === record.id ? 100 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%').wordBreak(WordBreak.BREAK_ALL)
        Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
          this.badge(dnsInitiatorLabel(record.initiator))
          if (record.cached) { this.badge('缓存') }
          Text(record.upstream || '上游未报告').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
            .wordBreak(WordBreak.BREAK_ALL)
        }.width('100%')
      }.width('100%').alignItems(HorizontalAlign.Start)
    }
    .width('100%').padding(20).borderRadius(DETAIL_CARD_RADIUS).backgroundColor(this.theme.surface)
    .accessibilityText(`${record.host}，${record.type}，${record.duration} 毫秒，点击展开或收起完整结果`)
    .onClick((): void => { this.expandedId = this.expandedId === record.id ? '' : record.id; })
  }

  build() {
    Column() {
      SecondaryPageHeader({ title: 'DNS 查询', contentPadding: this.contentPadding,
        onBack: this.onBack, actions: (): void => { this.actions(); } })
      if (this.searching) {
        Column() {
          TextInput({ placeholder: '搜索域名、结果、类型或上游', text: this.query })
            .id('dns-search').height(CONTROL_HEIGHT).fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
            .placeholderFont({ size: themeFontSize(BODY_FONT_SIZE, this.theme), family: this.theme.fontFamily })
            .fontColor($r('app.color.content_primary')).placeholderColor($r('app.color.content_secondary'))
            .backgroundColor(this.theme.surface).borderRadius(24)
            .accessibilityText('搜索 DNS 查询').onChange((value: string): void => { this.query = value; })
        }.padding({ left: this.contentPadding, right: this.contentPadding, bottom: 12 }).transition(revealTransition())
      }
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.status_error'))
          .padding({ left: this.contentPadding, right: this.contentPadding, bottom: 8 })
      }
      Stack() {
        if (filterDnsQueries(this.records, this.query).length === 0) {
          EmptyStateBackground({ icon: $r('app.media.nav_dns'),
            title: !this.available ? 'Core 尚未就绪' : (this.query.length > 0 ? '没有匹配的 DNS 查询' : '暂无 DNS 查询'),
            description: !this.available ? '启动 Core 后查看实际 DNS 解析记录。' :
              (this.query.length > 0 ? '尝试其他关键词。' : '使用内核 DNS 解析后，最近 200 条查询会自动出现在这里。') })
        }
        List({ space: 12 }) {
          ForEach(filterDnsQueries(this.records, this.query), (record: DnsQueryRecord) => {
            ListItem() { this.queryCard(record) }.transition(revealTransition())
          }, (record: DnsQueryRecord): string => record.id)
        }
        .width('100%').height('100%').contentStartOffset(12).contentEndOffset(32).scrollBar(BarState.Off)
      }.width('100%').layoutWeight(1).padding({ left: this.contentPadding, right: this.contentPadding })
    }.width('100%').height('100%').backgroundColor(this.theme.background)
  }
}
