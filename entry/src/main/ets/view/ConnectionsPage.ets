import { AppTheme } from '../model/ThemeModels';
import { ThemeAlertDialog } from '../components/ThemeAlertDialog';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { EmptyStateBackground } from '../components/EmptyStateBackground';
import { SecondaryPageHeader } from '../components/SecondaryPageHeader';
import { HeaderIconButton } from '../components/HeaderIconButton';
import { ConnectionRoute } from '../components/ConnectionRoute';
import { ConnectionSnapshot, RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { formatBytes, formatSpeed } from '../utils/RuntimeUtils';
import { elapsedLabel, formatRecordTime, requestEndpoint } from '../utils/ActivityUtils';
import { revealTransition } from '../utils/AnimationUtils';
import { feedbackService } from '../services/FeedbackService';
import { runtimeStore } from '../stores/RuntimeStore';
import { CONTROL_HEIGHT, DETAIL_CARD_RADIUS, BODY_FONT_SIZE, CAPTION_FONT_SIZE } from '../constants/UiConstants';

interface ConnectionCardData { connection: ConnectionSnapshot; }

@Component
export struct ConnectionsPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop @Watch('updateActivity') isActive: boolean = true;
  @Prop contentPadding: number = 16;
  @Link query: string;
  onBack: () => void = (): void => {};
  @State available: boolean = false;
  @State connections: ConnectionSnapshot[] = [];
  @State recordsById: Map<string, ConnectionSnapshot> = new Map<string, ConnectionSnapshot>();
  @State busyKey: string = '';
  @State searching: boolean = false;
  @State expandedId: string = '';
  private unsubscribe: (() => void) | undefined;
  private alertDialog: CustomDialogController | undefined;
  private cancelConfirmation: (() => void) | undefined;

  aboutToAppear(): void {
    this.searching = this.query.length > 0;
    this.updateActivity();
  }

  private updateActivity(): void {
    this.stopObserving();
    if (!this.isActive) { return; }
    this.unsubscribe = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      this.available = snapshot.proxyEnabled;
      const records = new Map<string, ConnectionSnapshot>();
      snapshot.connections.forEach((item: ConnectionSnapshot): void => { records.set(item.id, item); });
      this.recordsById = records;
      this.connections = snapshot.connections;
      this.busyKey = snapshot.busyKey;
    });
    runtimeStore.refresh();
  }

  aboutToDisappear(): void { this.stopObserving(); }

  private stopObserving(): void {
    this.unsubscribe?.();
    this.unsubscribe = undefined;
    this.cancelConfirmation?.();
    this.alertDialog?.close();
    this.connections = [];
    this.recordsById = new Map<string, ConnectionSnapshot>();
    this.expandedId = '';
  }

  private async closeConnection(id: string): Promise<void> {
    try {
      await runtimeStore.closeConnection(id);
      feedbackService.success('连接已关闭');
    } catch (error) {
      feedbackService.error((error as Error).message || '关闭连接失败，请重试');
    }
  }

  private async closeAllConnections(): Promise<void> {
    const confirmed = await new Promise<boolean>((resolve): void => {
      this.cancelConfirmation = (): void => { resolve(false); };
      this.alertDialog = new CustomDialogController({
        builder: ThemeAlertDialog({ title: '关闭全部连接？', message: '当前传输会中断，应用可能自动重新建立连接。',
          confirmLabel: '全部关闭', destructive: true, onConfirm: (): void => { resolve(true); },
          onCancel: this.cancelConfirmation }),
        cancel: this.cancelConfirmation, customStyle: true, alignment: DialogAlignment.Center
      });
      this.alertDialog.open();
    });
    this.cancelConfirmation = undefined;
    if (!confirmed) { return; }
    try {
      await runtimeStore.closeAllConnections();
      feedbackService.success('全部连接已关闭');
    } catch (error) {
      feedbackService.error((error as Error).message || '关闭连接失败，请重试');
    }
  }

  private visibleConnections(): ConnectionSnapshot[] {
    const keyword = this.query.trim().toLowerCase();
    return this.connections.filter((connection: ConnectionSnapshot): boolean =>
      [connection.host, connection.destination, connection.source, connection.process,
        connection.rule, connection.rulePayload, connection.chains.join(' ')].join(' ').toLowerCase().includes(keyword));
  }

  @Builder
  private actions() {
    Row({ space: 8 }) {
      HeaderIconButton({ label: this.searching ? '收起连接搜索' : '搜索实时连接',
        onActivate: (): void => { this.searching = !this.searching; } })
      HeaderIconButton({ icon: $r('app.media.action_clear'), label: '关闭全部连接',
        available: this.available && this.connections.length > 0, busy: this.busyKey.length > 0,
        onActivate: (): void => {
          this.closeAllConnections().catch((): void => { feedbackService.error('无法完成关闭操作，请重试'); });
        } })
    }
  }

  @Builder
  private connectionCard(data: ConnectionCardData) {
    Column({ space: 4 }) {
      Row({ space: 8 }) {
        Text(`${elapsedLabel(data.connection.start)}  ${data.connection.network.toUpperCase()}`)
          .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).layoutWeight(1)
        Column({ space: 2 }) {
          Text(`↑ ${formatSpeed(data.connection.uploadSpeed ?? 0)}`)
            .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
          Text(`↓ ${formatSpeed(data.connection.downloadSpeed ?? 0)}`)
            .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
        }.alignItems(HorizontalAlign.End)
        HeaderIconButton({ icon: $r('app.media.action_close_connection'),
          label: `关闭 ${requestEndpoint(data.connection.host, data.connection.destination)} 的连接`,
          available: this.available && this.busyKey.length === 0, busy: this.busyKey === `connection:${data.connection.id}`,
          onActivate: (): void => { this.closeConnection(data.connection.id); } })
      }.width('100%')
      Button({ type: ButtonType.Normal }) {
        Column({ space: 10 }) {
          Text(requestEndpoint(data.connection.host, data.connection.destination)).fontSize(themeFontSize(18, this.theme)).fontFamily(this.theme.fontFamily).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.content_primary')).width('100%').wordBreak(WordBreak.BREAK_ALL)
          if (data.connection.host.length > 0) {
            Text(data.connection.destination).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary'))
              .width('100%').wordBreak(WordBreak.BREAK_ALL)
          }
          ConnectionRoute({ rule: data.connection.rule, payload: data.connection.rulePayload,
            chains: data.connection.chains.slice().reverse() })
          Text(data.connection.process || data.connection.source || '来源未报告').fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor($r('app.color.content_secondary')).width('100%').wordBreak(WordBreak.BREAK_ALL)
          if (this.expandedId === data.connection.id) {
            Column({ space: 8 }) {
              Divider().color(this.theme.divider)
              Text(`开始于 ${formatRecordTime(data.connection.start)}`).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
                .fontColor($r('app.color.content_secondary')).width('100%')
              Text(`${data.connection.type} · ↑ ${formatBytes(data.connection.upload)}  ↓ ${formatBytes(data.connection.download)}`)
                .fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily).fontColor($r('app.color.content_secondary')).width('100%')
              Text(`来源：${data.connection.source}`).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
                .fontColor($r('app.color.content_secondary')).width('100%').wordBreak(WordBreak.BREAK_ALL)
            }.width('100%').transition(revealTransition())
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }
      .width('100%').padding({ top: 8, bottom: 4 }).borderRadius(12).backgroundColor(Color.Transparent)
      .accessibilityText(`${requestEndpoint(data.connection.host, data.connection.destination)}，` +
        `${this.expandedId === data.connection.id ? '收起' : '展开'}连接详情`)
      .onClick((): void => { this.expandedId = this.expandedId === data.connection.id ? '' : data.connection.id; })
    }.width('100%').padding(20).borderRadius(DETAIL_CARD_RADIUS).backgroundColor(this.theme.surface)
  }

  build() {
    Column() {
      SecondaryPageHeader({ title: '实时连接', contentPadding: this.contentPadding,
        onBack: this.onBack, actions: (): void => { this.actions(); } })
      if (this.searching) {
        Column({ space: 8 }) {
          TextInput({ placeholder: '搜索主机、地址、进程或链路', text: this.query })
            .id('connection-search').height(CONTROL_HEIGHT).fontSize(themeFontSize(BODY_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
            .placeholderFont({ size: themeFontSize(BODY_FONT_SIZE, this.theme), family: this.theme.fontFamily })
            .fontColor($r('app.color.content_primary')).placeholderColor($r('app.color.content_secondary'))
            .backgroundColor(this.theme.surface).borderRadius(24)
            .accessibilityText('搜索实时连接').onChange((value: string): void => { this.query = value; })
          Text(`${this.visibleConnections().length} 个活动连接`).fontSize(themeFontSize(CAPTION_FONT_SIZE, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor($r('app.color.content_secondary')).width('100%')
        }
        .padding({ left: this.contentPadding, right: this.contentPadding, bottom: 12 }).transition(revealTransition())
      }
      Stack() {
        if (!this.available || this.visibleConnections().length === 0) {
          EmptyStateBackground({ icon: $r('app.media.nav_connections'),
            title: !this.available ? '代理未运行' : (this.query.length > 0 ? '没有匹配的连接' : '当前没有活动连接'),
            description: !this.available ? '仅在代理运行时显示活动连接，关闭后立即清空。' :
              (this.query.length > 0 ? '尝试其他关键词。' : '有新的网络连接时会自动出现在这里。') })
        }
        List({ space: 12 }) {
          if (this.available) {
            ForEach(this.visibleConnections(), (connection: ConnectionSnapshot) => {
              ListItem() { this.connectionCard({ connection: this.recordsById.get(connection.id) ?? connection }) }.transition(revealTransition())
            }, (connection: ConnectionSnapshot): string => connection.id)
          }
        }
        .width('100%').height('100%').contentStartOffset(12).contentEndOffset(32).scrollBar(BarState.Off)
      }.width('100%').layoutWeight(1).padding({ left: this.contentPadding, right: this.contentPadding })
    }.width('100%').height('100%').backgroundColor(this.theme.background)
  }
}
