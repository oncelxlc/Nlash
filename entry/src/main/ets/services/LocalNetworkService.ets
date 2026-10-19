import { BusinessError } from '@kit.BasicServicesKit';
import { connection, http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { IpNetworkType, IpQuality, PublicNetworkSnapshot } from '../model/RuntimeModels';
import { ProxyState } from '../model/VpnModels';

const PUBLIC_IPV4_URL = 'https://api.ipify.org';
const FALLBACK_IPV4_URL = 'https://api-ipv4.ip.sb/ip';
const IP_INFO_BASE_URL = 'https://api.ipquery.io/';
const GEOIP_BASE_URL = 'https://api.ip.sb/geoip/';
const HTTP_TIMEOUT_MS = 10000;
const REFRESH_DEBOUNCE_MS = 600;
const NETWORK_LOG_DOMAIN = 0xD001;
const NETWORK_LOG_TAG = 'NlashNetwork';

interface GeoIpResponse {
  ip?: string;
  country?: string;
  country_code?: string;
  organization?: string;
  asn_organization?: string;
  isp?: string;
}

interface IpQueryIsp {
  org?: string;
  isp?: string;
}

interface IpQueryLocation {
  country?: string;
  country_code?: string;
}

interface IpQueryRisk {
  is_mobile?: boolean;
  is_datacenter?: boolean;
  is_vpn?: boolean;
  is_proxy?: boolean;
  is_tor?: boolean;
  risk_score?: number;
}

interface IpQueryResponse {
  ip?: string;
  isp?: IpQueryIsp;
  location?: IpQueryLocation;
  risk?: IpQueryRisk;
}

export type PublicNetworkRequest = (url: string, accept: string) => Promise<string>;

export type PublicNetworkListener = (snapshot: PublicNetworkSnapshot) => void;

export function shouldApplyNetworkResult(resultGeneration: number, currentGeneration: number,
  serviceActive: boolean): boolean {
  return resultGeneration === currentGeneration && serviceActive;
}

export function shouldRefreshPublicNetworkAfterProxyStateChange(previousState: ProxyState,
  currentState: ProxyState): boolean {
  return previousState !== currentState &&
    (currentState === ProxyState.ENABLED || currentState === ProxyState.DISABLED);
}

/** 只有正在工作的代理切换节点才影响公网出口，离线预选不触发探测。 */
export function shouldRefreshPublicNetworkAfterProxySelection(previousProxy: string, currentProxy: string,
  runtimeAvailable: boolean, proxyConnected: boolean): boolean {
  return previousProxy !== currentProxy && runtimeAvailable && proxyConnected;
}

export function isValidIpv4(value: string): boolean {
  const parts = value.trim().split('.');
  if (parts.length !== 4) {
    return false;
  }
  return parts.every((part: string): boolean => {
    if (!/^\d{1,3}$/.test(part) || (part.length > 1 && part.startsWith('0'))) {
      return false;
    }
    const number = Number(part);
    return Number.isInteger(number) && number >= 0 && number <= 255;
  });
}

export function countryCodeFlag(countryCode: string): string {
  const normalized = countryCode.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(normalized)) {
    return '🌐';
  }
  return String.fromCodePoint(
    normalized.charCodeAt(0) - 65 + 0x1F1E6,
    normalized.charCodeAt(1) - 65 + 0x1F1E6);
}

/** 地理信息必须对应刚探测的出口 IPv4，避免将不同请求的地址和地区组合展示。 */
export function parseGeoIpResponse(raw: string, expectedIpv4: string): PublicNetworkSnapshot {
  const parsed = JSON.parse(raw) as GeoIpResponse;
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw new Error('地理位置服务响应无效');
  }
  const ipv4 = typeof parsed.ip === 'string' ? parsed.ip.trim() : '';
  if (!isValidIpv4(ipv4) || ipv4 !== expectedIpv4) {
    throw new Error('地理位置服务返回的 IPv4 不匹配');
  }
  const country = typeof parsed.country === 'string' && parsed.country.trim().length > 0 ?
    parsed.country.trim() : '未知地区';
  const countryCode = typeof parsed.country_code === 'string' ? parsed.country_code.trim().toUpperCase() : '';
  return {
    publicIpv4: ipv4,
    country: country,
    countryCode: /^[A-Z]{2}$/.test(countryCode) ? countryCode : '',
    organization: networkText(parsed.organization) || networkText(parsed.asn_organization) || networkText(parsed.isp),
    checking: false,
    lastSuccessAt: Date.now(),
    errorMessage: ''
  };
}

function networkText(value: string | undefined): string {
  return typeof value === 'string' ? value.replace(/[\u0000-\u001f\u007f]/g, '').trim().substring(0, 160) : '';
}

/** 风险分 0–19 为优、20–59 为普通、60–100 为较差；机房／VPN 至少普通，Tor／公开代理为较差。 */
export function parseIpQueryResponse(raw: string, expectedIpv4: string): PublicNetworkSnapshot {
  const parsed = JSON.parse(raw) as IpQueryResponse;
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed) ||
    typeof parsed.ip !== 'string' || !isValidIpv4(parsed.ip) || parsed.ip.trim() !== expectedIpv4) {
    throw new Error('IP 信息服务返回的 IPv4 不匹配');
  }
  const risk = parsed.risk;
  const score = risk?.risk_score;
  const validScore = typeof score === 'number' && Number.isInteger(score) && score >= 0 && score <= 100;
  const completeRisk = validScore && typeof risk?.is_vpn === 'boolean' &&
    typeof risk?.is_proxy === 'boolean' && typeof risk?.is_tor === 'boolean' &&
    typeof risk?.is_datacenter === 'boolean';
  let quality = IpQuality.UNKNOWN;
  if (completeRisk && score !== undefined) {
    quality = risk?.is_tor === true || risk?.is_proxy === true || score >= 60 ? IpQuality.POOR :
      (score >= 20 || risk?.is_vpn === true || risk?.is_datacenter === true ? IpQuality.NORMAL : IpQuality.GOOD);
  }
  const countryCode = networkText(parsed.location?.country_code).toUpperCase();
  return {
    publicIpv4: expectedIpv4,
    country: networkText(parsed.location?.country) || '未知地区',
    countryCode: /^[A-Z]{2}$/.test(countryCode) ? countryCode : '',
    organization: networkText(parsed.isp?.org) || networkText(parsed.isp?.isp),
    networkType: risk?.is_datacenter === true ? IpNetworkType.HOSTING :
      (risk?.is_mobile === true ? IpNetworkType.MOBILE :
        (risk?.is_datacenter === false && risk?.is_mobile === false ? IpNetworkType.NON_HOSTING : IpNetworkType.UNKNOWN)),
    quality: quality,
    riskScore: validScore ? score : undefined,
    qualityError: completeRisk ? '' : 'IP 质量数据不完整',
    checking: false, lastSuccessAt: Date.now(), errorMessage: ''
  };
}

/** 先锁定实际出口 IPv4，再查对应地址；质量服务失败时只降级信息，不伪造评估。 */
export async function resolvePublicNetwork(request: PublicNetworkRequest): Promise<PublicNetworkSnapshot> {
  let ipv4: string;
  try {
    ipv4 = (await request(PUBLIC_IPV4_URL, 'text/plain')).trim();
    if (!isValidIpv4(ipv4)) { throw new Error('公网地址服务未返回有效 IPv4'); }
  } catch (_error) {
    ipv4 = (await request(FALLBACK_IPV4_URL, 'text/plain')).trim();
    if (!isValidIpv4(ipv4)) { throw new Error('公网地址服务未返回有效 IPv4'); }
  }
  try {
    return parseIpQueryResponse(await request(`${IP_INFO_BASE_URL}${ipv4}`, 'application/json'), ipv4);
  } catch (_error) {
    let snapshot: PublicNetworkSnapshot;
    try {
      snapshot = parseGeoIpResponse(await request(`${GEOIP_BASE_URL}${ipv4}`, 'application/json'), ipv4);
    } catch (_geoError) {
      snapshot = { publicIpv4: ipv4, country: '未知地区', countryCode: '', checking: false,
        lastSuccessAt: Date.now(), errorMessage: 'IP 信息查询失败，点击国家代码重试' };
    }
    snapshot.quality = IpQuality.UNKNOWN;
    snapshot.qualityError = 'IP 质量查询失败，点击国家代码重试';
    return snapshot;
  }
}

/** 监听网络变化并探测公网出口；刷新去抖、串行执行，以 generation 丢弃失效结果。 */
class PublicNetworkService {
  private snapshot: PublicNetworkSnapshot = {
    publicIpv4: '未知', country: '未知地区', countryCode: '', checking: false, errorMessage: ''
  };
  private listeners: Set<PublicNetworkListener> = new Set<PublicNetworkListener>();
  private networkConnection: connection.NetConnection | undefined = undefined;
  private generation: number = 0;
  private refreshTimer: number = -1;
  private refreshInFlight: boolean = false;
  private refreshPending: boolean = false;
  private initialized: boolean = false;

  private readonly availableHandler = (_handle: connection.NetHandle): void => this.refresh();
  private readonly propertiesHandler = (_info: connection.NetConnectionPropertyInfo): void => this.refresh();
  private readonly lostHandler = (_handle: connection.NetHandle): void => this.refresh();
  private readonly unavailableHandler = (): void => {
    if (!this.initialized) {
      return;
    }
    this.generation += 1;
    this.refreshPending = false;
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
    this.snapshot = this.withStatus(false, '当前网络不可用');
    this.publish();
  };

  initialize(): void {
    if (this.initialized) {
      return;
    }
    this.initialized = true;
    this.start();
  }

  shutdown(): void {
    if (!this.initialized) {
      return;
    }
    this.initialized = false;
    this.stop();
    this.listeners.clear();
  }

  getSnapshot(): PublicNetworkSnapshot {
    return this.copySnapshot();
  }

  subscribe(listener: PublicNetworkListener): () => void {
    this.listeners.add(listener);
    listener(this.copySnapshot());
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  refresh(): void {
    if (!this.initialized) {
      return;
    }
    // 出口可能已改变，立即使在途结果失效；多次刷新仍合并为下一轮。
    this.generation += 1;
    this.snapshot = this.withStatus(true, '');
    this.publish();
    if (this.refreshInFlight) {
      this.refreshPending = true;
      return;
    }
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
    }
    this.refreshTimer = setTimeout((): void => {
      this.refreshTimer = -1;
      this.beginRefresh();
    }, REFRESH_DEBOUNCE_MS);
  }

  private start(): void {
    if (this.networkConnection !== undefined) {
      return;
    }
    const monitor = connection.createNetConnection();
    this.networkConnection = monitor;
    monitor.on('netAvailable', this.availableHandler);
    monitor.on('netConnectionPropertiesChange', this.propertiesHandler);
    monitor.on('netLost', this.lostHandler);
    monitor.on('netUnavailable', this.unavailableHandler);
    monitor.register((error: BusinessError): void => {
      if (error) {
        hilog.warn(NETWORK_LOG_DOMAIN, NETWORK_LOG_TAG, 'network monitor registration failed code=%{public}d',
          error.code);
        this.unavailableHandler();
      } else {
        hilog.info(NETWORK_LOG_DOMAIN, NETWORK_LOG_TAG, 'network monitor registered');
      }
    });
    // Application startup must not depend on a delayed network callback to see a result.
    this.beginRefresh();
  }

  private stop(): void {
    this.generation += 1;
    this.refreshPending = false;
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
    const monitor = this.networkConnection;
    this.networkConnection = undefined;
    if (monitor !== undefined) {
      monitor.unregister((_error: BusinessError): void => {
      });
    }
  }

  private beginRefresh(): void {
    if (!this.initialized) {
      return;
    }
    if (this.refreshInFlight) {
      this.refreshPending = true;
      return;
    }
    this.refreshInFlight = true;
    this.refreshPending = false;
    const generation = ++this.generation;
    hilog.info(NETWORK_LOG_DOMAIN, NETWORK_LOG_TAG, 'public network refresh started generation=%{public}d', generation);
    this.snapshot = this.withStatus(true, '');
    this.publish();
    const operation = resolvePublicNetwork((url: string, accept: string): Promise<string> => this.requestText(url, accept));
    operation.then((snapshot: PublicNetworkSnapshot): void => {
      if (!shouldApplyNetworkResult(generation, this.generation, this.initialized)) {
        return;
      }
      this.snapshot = snapshot;
      hilog.info(NETWORK_LOG_DOMAIN, NETWORK_LOG_TAG, 'public network refresh succeeded generation=%{public}d',
        generation);
      this.publish();
    }, (): void => {
      if (!shouldApplyNetworkResult(generation, this.generation, this.initialized)) {
        return;
      }
      this.snapshot = this.withStatus(false, '公网 IP 刷新失败');
      hilog.warn(NETWORK_LOG_DOMAIN, NETWORK_LOG_TAG, 'public network refresh failed generation=%{public}d',
        generation);
      this.publish();
    }).then((): void => {
      this.finishRefresh();
    });
  }

  private finishRefresh(): void {
    this.refreshInFlight = false;
    if (this.refreshPending && this.initialized) {
      this.refreshPending = false;
      this.refresh();
    }
  }

  private async requestText(url: string, accept: string): Promise<string> {
    const request = http.createHttp();
    let timeoutId = -1;
    try {
      const operation = request.request(url, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        usingCache: false,
        connectTimeout: HTTP_TIMEOUT_MS,
        readTimeout: HTTP_TIMEOUT_MS,
        header: { 'User-Agent': 'Nlash/1.0', 'Accept': accept }
      });
      const timeout = new Promise<http.HttpResponse>((_resolve: (value: http.HttpResponse) => void,
        reject: (reason: Error) => void): void => {
        timeoutId = setTimeout((): void => reject(new Error('公网地址请求超时')), HTTP_TIMEOUT_MS);
      });
      const response = await Promise.race([operation, timeout]);
      const status = Number(response.responseCode);
      if (status < 200 || status >= 300 || response.resultType !== http.HttpDataType.STRING) {
        throw new Error(`公网地址服务返回 HTTP ${status}`);
      }
      if ((response.result as string).length > 65536) { throw new Error('IP 信息响应过大'); }
      return response.result as string;
    } finally {
      if (timeoutId >= 0) {
        clearTimeout(timeoutId);
      }
      request.destroy();
    }
  }

  // 刷新中或失败时保留上次成功数据，通过状态字段提示其新鲜度。
  private withStatus(checking: boolean, errorMessage: string): PublicNetworkSnapshot {
    return {
      publicIpv4: this.snapshot.publicIpv4,
      country: this.snapshot.country,
      countryCode: this.snapshot.countryCode,
      organization: this.snapshot.organization,
      networkType: this.snapshot.networkType,
      quality: checking || errorMessage.length > 0 ? IpQuality.UNKNOWN : this.snapshot.quality,
      riskScore: checking || errorMessage.length > 0 ? undefined : this.snapshot.riskScore,
      qualityError: checking ? '' : (errorMessage || this.snapshot.qualityError),
      checking: checking,
      lastSuccessAt: this.snapshot.lastSuccessAt,
      errorMessage: errorMessage
    };
  }

  private copySnapshot(): PublicNetworkSnapshot {
    return this.withStatus(this.snapshot.checking, this.snapshot.errorMessage);
  }

  private publish(): void {
    const snapshot = this.copySnapshot();
    this.listeners.forEach((listener: PublicNetworkListener): void => listener(snapshot));
  }
}

export const publicNetworkService = new PublicNetworkService();
