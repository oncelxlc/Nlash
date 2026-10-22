import { AppTheme } from '../model/ThemeModels';
import { DEFAULT_APP_THEME, themeFontSize } from '../utils/ThemeUtils';
import { GeneralSettings } from '../model/GeneralSettingsModels';
import { DEFAULT_GENERAL_SETTINGS } from '../constants/GeneralSettingsConstants';
import { SettingsStoreSnapshot } from '../model/SettingsModels';
import { RuntimeStoreSnapshot } from '../model/RuntimeModels';
import { generalSettingsService } from '../services/GeneralSettingsService';
import { coreClient } from '../services/CoreClient';
import { feedbackService } from '../services/FeedbackService';
import { settingsStore } from '../stores/SettingsStore';
import { runtimeStore } from '../stores/RuntimeStore';
import { formatHostOverrides, parseHostOverrides, parseMixedPort } from '../utils/GeneralSettingsUtils';
import { resolveContentWidth, resolveResponsiveMetrics } from '../utils/ResponsiveUtils';
import { selectionAnimation } from '../utils/AnimationUtils';
import { FadingScrollLayout } from '../components/FadingScrollLayout';
import { SecondaryPageHeader } from '../components/SecondaryPageHeader';
import { GeneralInputDialog } from '../components/GeneralInputDialog';
import { SingleChoiceControl } from '../components/SingleChoiceControl';
import { LOG_LEVELS, LOG_LEVEL_LABELS } from '../constants/LogConstants';

interface GeneralToggleParams {
  key: string;
  title: string;
  value: boolean;
  change: (settings: GeneralSettings, value: boolean) => void;
  last?: boolean;
}

interface GeneralEditParams {
  title: string;
  value: string;
  action: () => void;
  last?: boolean;
  requiresCore?: boolean;
}

@Component
export struct GeneralPage {
  @StorageProp('appTheme') theme: AppTheme = DEFAULT_APP_THEME;
  @Prop @Watch('updateActivity') isActive: boolean = true;
  onBack: () => void = (): void => {};
  @State settings: GeneralSettings = DEFAULT_GENERAL_SETTINGS;
  @State testUrl: string = settingsStore.getSnapshot().settings.delayTestUrl;
  @State saving: boolean = false;
  @State available: boolean = false;
  @State supported: boolean = true;
  @State loaded: boolean = false;
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State headerInset: number = 0;
  @State contentPadding: number = 16;
  private active: boolean = false;
  private generation: number = 0;
  private unsubscribeRuntime: (() => void) | undefined;
  private unsubscribeSettings: (() => void) | undefined;
  private dialog: CustomDialogController | undefined;

  aboutToAppear(): void { this.updateActivity(); }

  private updateActivity(): void {
    this.stopObserving();
    if (!this.isActive) { return; }
    this.active = true;
    try { this.supported = coreClient.getVersion() !== 'unavailable/non-arm64'; }
    catch (_error) { this.supported = false; }
    if (!this.supported) { this.errorMessage = '当前设备不支持 Mihomo Core，可修改测试链接。'; }
    this.unsubscribeSettings = settingsStore.subscribe((snapshot: SettingsStoreSnapshot): void => {
      this.testUrl = snapshot.settings.delayTestUrl;
    });
    this.unsubscribeRuntime = runtimeStore.subscribe((snapshot: RuntimeStoreSnapshot): void => {
      const changed = this.available !== snapshot.coreAvailable;
      this.available = snapshot.coreAvailable;
      if (changed && !this.saving) { this.generation += 1; this.loaded = false; this.errorMessage = ''; }
      if (this.supported && !this.loaded && !this.loading && !this.saving && this.errorMessage.length === 0) {
        this.load();
      }
    });
    if (this.supported) { this.load(); }
  }

  aboutToDisappear(): void { this.stopObserving(); }

  private stopObserving(): void {
    this.active = false;
    this.generation += 1;
    this.loaded = false;
    this.unsubscribeRuntime?.();
    this.unsubscribeRuntime = undefined;
    this.unsubscribeSettings?.();
    this.unsubscribeSettings = undefined;
    this.dialog?.close();
  }

  private async load(): Promise<void> {
    if (this.loading) { return; }
    this.loading = true;
    const generation = this.generation;
    try {
      const settings = await generalSettingsService.load();
      if (this.active && generation === this.generation) {
        this.settings = settings;
        this.loaded = true;
        this.errorMessage = '';
      }
    } catch (error) {
      if (this.active && generation === this.generation) { this.errorMessage = (error as Error).message; }
    } finally { this.loading = false; }
  }

  private async save(change: (settings: GeneralSettings) => void): Promise<void> {
    if (this.saving || !this.loaded) { throw new Error('设置尚未读取，请稍后重试'); }
    const previous = this.settings;
    const next = JSON.parse(JSON.stringify(previous)) as GeneralSettings;
    change(next);
    this.saving = true;
    this.settings = next;
    this.errorMessage = '';
    try {
      const saved = await generalSettingsService.save(next);
      if (this.active) { this.settings = saved; this.loaded = true; }
      feedbackService.success(this.available ? '常规设置已应用' : '常规设置已保存，下次启动 Core 时应用');
    } catch (error) {
      if (this.active) { this.settings = previous; }
      throw new Error((error as Error).message || '保存失败，请重试');
    } finally { this.saving = false; }
  }

  private async toggle(change: (settings: GeneralSettings) => void): Promise<void> {
    try { await this.save(change); }
    catch (error) {
      this.errorMessage = (error as Error).message || '保存失败，请重试';
      feedbackService.error(this.errorMessage);
    }
  }

  private edit(title: string, hint: string, value: string, submit: (value: string) => Promise<void>,
    multiline: boolean = false, secret: boolean = false, numeric: boolean = false): void {
    this.dialog = new CustomDialogController({
      builder: GeneralInputDialog({ title: title, hint: hint, initialInput: value, multiline: multiline,
        secret: secret, numeric: numeric, onSubmit: submit }),
      customStyle: true, autoCancel: false, alignment: DialogAlignment.Center,
      openAnimation: selectionAnimation(220), closeAnimation: selectionAnimation(140)
    });
    this.dialog.open();
  }

  @Builder
  private sectionTitle(title: string) {
    Text(title).fontSize(themeFontSize(13, this.theme)).fontFamily(this.theme.fontFamily)
      .fontColor($r('app.color.content_secondary')).width('100%').padding({ left: 16, top: 20, bottom: 4 })
  }

  @Builder
  private note(text: string) {
    Text(text).fontSize(themeFontSize(13, this.theme)).fontFamily(this.theme.fontFamily)
      .fontColor($r('app.color.content_secondary')).width('100%').padding({ left: 16, right: 16 })
  }

  @Builder
  private separator() { Divider().color(this.theme.divider).margin({ left: 16, right: 16 }) }

  @Builder
  private toggleRow($$: GeneralToggleParams) {
    Row({ space: 16 }) {
      Text($$.title).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
        .fontColor($r('app.color.content_primary')).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: $$.value })
        .id(`general-${$$.key}`).width(52).height(32).selectedColor(this.theme.accent)
        .responseRegion({ x: -4, y: -8, width: 60, height: 48 })
        .enabled(this.loaded && !this.saving).accessibilityText($$.title)
        .onChange((value: boolean): void => {
          if (value !== $$.value) {
            this.toggle((next: GeneralSettings): void => { $$.change(next, value); });
          }
        })
    }.width('100%').constraintSize({ minHeight: 60 }).padding({ left: 16, right: 16, top: 6, bottom: 6 })
    if (!$$.last) { this.separator() }
  }

  @Builder
  private editRow($$: GeneralEditParams) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 16 }) {
        Column({ space: 3 }) {
          Text($$.title).fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor($r('app.color.content_primary')).width('100%')
          Text($$.value).fontSize(themeFontSize(13, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor($r('app.color.content_secondary')).width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Image($r('app.media.action_chevron_down')).width(18).height(18).rotate({ angle: -90 })
          .fillColor($r('app.color.content_secondary')).accessibilityLevel('no')
      }.width('100%')
    }.id(`general-edit-${$$.title}`).width('100%').constraintSize({ minHeight: 64 }).borderRadius(0)
      .padding({ left: 16, right: 16, top: 12, bottom: 12 }).backgroundColor(Color.Transparent)
      .enabled(!this.saving && ($$.requiresCore === false || this.loaded))
      .accessibilityText(`${$$.title}，${$$.value}`).onClick($$.action)
    if (!$$.last) { this.separator() }
  }

  @Builder
  private inboundSection() {
    this.sectionTitle('入站')
    Column() {
      this.editRow({ title: '端口', value: `${this.settings.mixedPort}`, action: (): void => {
        this.edit('端口', 'HTTP / SOCKS 混合端口，0 表示关闭。', `${this.settings.mixedPort}`,
          async (value: string): Promise<void> => {
            const port = parseMixedPort(value);
            await this.save((next: GeneralSettings): void => { next.mixedPort = port; });
          }, false, false, true);
      } })
      this.toggleRow({ key: 'allow-lan', title: '局域网代理', value: this.settings.allowLan,
        change: (next: GeneralSettings, value: boolean): void => { next.allowLan = value; } })
      this.toggleRow({ key: 'controller', title: '外部控制器', value: this.settings.externalController,
        change: (next: GeneralSettings, value: boolean): void => { next.externalController = value; } })
      if (this.settings.externalController) {
        this.editRow({ title: '控制器密钥', value: '••••••••', action: (): void => {
          this.edit('控制器密钥', '控制器需要此密钥进行认证。', this.settings.controllerSecret,
            async (value: string): Promise<void> => {
              await this.save((next: GeneralSettings): void => { next.controllerSecret = value.trim(); });
            }, false, true);
        } })
      }
      this.toggleRow({ key: 'authentication', title: '认证', value: this.settings.authentication,
        last: !this.settings.authentication,
        change: (next: GeneralSettings, value: boolean): void => { next.authentication = value; } })
      if (this.settings.authentication) {
        this.editRow({ title: '账号', value: this.settings.username, action: (): void => {
          this.edit('账号', '本地代理认证账号，不含冒号。', this.settings.username,
            async (value: string): Promise<void> => {
              await this.save((next: GeneralSettings): void => { next.username = value.trim(); });
            });
        } })
        this.editRow({ title: '密码', value: '••••••••', last: true, action: (): void => {
          this.edit('密码', '本地代理认证密码。', this.settings.password,
            async (value: string): Promise<void> => {
              await this.save((next: GeneralSettings): void => { next.password = value; });
            }, false, true);
        } })
      }
    }.width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
    this.note('局域网代理允许同一网络的设备连接。控制器仅监听本机 127.0.0.1:9090。\n开启认证后，HTTP / SOCKS 代理需要账号密码。')
  }

  @Builder
  private connectionSection() {
    this.sectionTitle('连接')
    Column() {
      this.editRow({ title: '测试链接', value: this.testUrl, requiresCore: false, action: (): void => {
        this.edit('测试链接', '用于节点延迟测试的 HTTP(S) 地址。', this.testUrl,
          async (value: string): Promise<void> => {
            await settingsStore.setDelayTestUrl(value);
            feedbackService.success('测试链接已保存');
          });
      } })
      this.toggleRow({ key: 'unified-delay', title: '统一延迟', value: this.settings.unifiedDelay,
        change: (next: GeneralSettings, value: boolean): void => { next.unifiedDelay = value; } })
      this.toggleRow({ key: 'tcp-concurrent', title: 'TCP 并发', value: this.settings.tcpConcurrent,
        change: (next: GeneralSettings, value: boolean): void => { next.tcpConcurrent = value; } })
      this.toggleRow({ key: 'find-process', title: '查找进程', value: this.settings.findProcess,
        change: (next: GeneralSettings, value: boolean): void => { next.findProcess = value; } })
      this.toggleRow({ key: 'auto-close', title: '自动关闭连接', value: this.settings.autoCloseConnections,
        change: (next: GeneralSettings, value: boolean): void => { next.autoCloseConnections = value; } })
      this.toggleRow({ key: 'only-proxy', title: '仅统计代理流量', value: this.settings.onlyProxyTraffic, last: true,
        change: (next: GeneralSettings, value: boolean): void => { next.onlyProxyTraffic = value; } })
    }.width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
    this.note('自动关闭连接会在切换节点后断开已有连接。\n进程识别受系统权限限制，部分连接可能无法识别。切换流量统计范围后重新计数。')
  }

  @Builder
  private coreSection() {
    this.sectionTitle('内核')
    Column() {
      this.toggleRow({ key: 'ipv6', title: 'IPv6', value: this.settings.ipv6,
        change: (next: GeneralSettings, value: boolean): void => { next.ipv6 = value; } })
      this.editRow({ title: 'Hosts', value: this.settings.hosts.length === 0 ? '无' : `${this.settings.hosts.length} 条`, action: (): void => {
        this.edit('Hosts', '每行：域名 = IP 或域名。多个 IP 用逗号分隔；同名项覆盖订阅中的 Hosts。清空可移除自定义项。',
          formatHostOverrides(this.settings.hosts), async (value: string): Promise<void> => {
            const hosts = parseHostOverrides(value);
            await this.save((next: GeneralSettings): void => { next.hosts = hosts; });
          }, true);
      } })
      this.toggleRow({ key: 'system-dns', title: '追加系统 DNS', value: this.settings.appendSystemDns,
        change: (next: GeneralSettings, value: boolean): void => { next.appendSystemDns = value; } })
      this.toggleRow({ key: 'geo-memory', title: 'Geo 低内存模式', value: this.settings.geoMemoryMode, last: true,
        change: (next: GeneralSettings, value: boolean): void => { next.geoMemoryMode = value; } })
    }.width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
    this.note('开启 IPv6 后接收 IPv6 流量；代理运行时切换会短暂重连。\n系统 DNS 取自当前非 VPN 网络，追加至配置的上游 DNS。')
  }

  @Builder
  private header() {
    SecondaryPageHeader({ title: '常规', contentPadding: this.contentPadding, onBack: this.onBack })
  }

  @Builder
  private logSection() {
    this.sectionTitle('日志')
    Column() {
      this.toggleRow({ key: 'log-capture', title: '开启日志捕获', value: this.settings.logCapture,
        change: (next: GeneralSettings, value: boolean): void => { next.logCapture = value; } })
      Column({ space: 12 }) {
        Text('日志等级').fontSize(themeFontSize(16, this.theme)).fontFamily(this.theme.fontFamily)
          .fontColor($r('app.color.content_primary')).width('100%')
        SingleChoiceControl({ labels: LOG_LEVEL_LABELS, selectedIndex: LOG_LEVELS.indexOf(this.settings.logLevel),
          scrollable: true, isEnabled: this.loaded && !this.saving, accessibilityLabel: '日志等级',
          onChange: (index: number): void => {
            this.toggle((next: GeneralSettings): void => { next.logLevel = LOG_LEVELS[index]; });
          } })
      }.width('100%').padding(16)
    }.width('100%').borderRadius(24).clip(true).backgroundColor(this.theme.surface)
    this.note('捕获所选等级及更高等级的内核日志；静默时不捕获。最多保留最近 500 条、64 KiB 正文，仅驻留内存。关闭捕获后可继续查看和导出已有记录。')
  }

  @Builder
  private content() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.supported && !this.available) { this.note('Core 未运行，设置读取后可保存，下次启动时应用。') }
        if (this.loading || this.saving) { this.note(this.saving ? '正在应用设置…' : '正在读取设置…') }
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage).fontSize(themeFontSize(14, this.theme)).fontFamily(this.theme.fontFamily)
            .fontColor($r('app.color.status_error')).width('100%')
          if (!this.loaded && this.supported) {
            Button('重新读取').enabled(!this.loading).onClick((): void => { this.load(); })
          }
        }
        this.inboundSection()
        this.connectionSection()
        this.coreSection()
        this.logSection()
      }.width('100%').constraintSize({ maxWidth: 640 })
        .padding({ top: this.headerInset, bottom: 32, left: this.contentPadding, right: this.contentPadding })
    }.width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
  }

  build() {
    FadingScrollLayout({ topInset: $headerInset,
      header: (): void => { this.header(); }, content: (): void => { this.content(); }
    }).onAreaChange((_old: Area, area: Area): void => {
      this.contentPadding = resolveResponsiveMetrics(resolveContentWidth(area.width)).pagePadding;
    })
  }
}
