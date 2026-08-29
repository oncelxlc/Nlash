import { BusinessError } from '@kit.BasicServicesKit';
import { connection, http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { PublicNetworkSnapshot } from '../models/RuntimeModels';

const PUBLIC_IPV4_URL = 'https://api-ipv4.ip.sb/ip';
const GEOIP_BASE_URL = 'https://api.ip.sb/geoip/';
const HTTP_TIMEOUT_MS = 10000;
const REFRESH_DEBOUNCE_MS = 600;
const NETWORK_LOG_DOMAIN = 0xD001;
const NETWORK_LOG_TAG = 'NlashNetwork';

interface GeoIpResponse {
  ip?: string;
  country?: string;
  country_code?: string;
}

export type PublicNetworkListener = (snapshot: PublicNetworkSnapshot) => void;

export function shouldApplyNetworkResult(resultGeneration: number, currentGeneration: number,
  listenerCount: number): boolean {
  return resultGeneration === currentGeneration && listenerCount > 0;
}

export function isValidIpv4(value: string): boolean {
  const parts = value.trim().split('.');
  if (parts.length !== 4) {
    return false;
  }
  return parts.every((part: string): boolean => {
    if (part.length === 0 || (part.length > 1 && part.startsWith('0'))) {
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

export function parseGeoIpResponse(raw: string, expectedIpv4: string): PublicNetworkSnapshot {
  const parsed = JSON.parse(raw) as GeoIpResponse;
  const ipv4 = typeof parsed.ip === 'string' && isValidIpv4(parsed.ip) ? parsed.ip.trim() : expectedIpv4;
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
    checking: false,
    lastSuccessAt: Date.now(),
    errorMessage: ''
  };
}

class PublicNetworkService {
  private snapshot: PublicNetworkSnapshot = {
    publicIpv4: '未知', country: '未知地区', countryCode: '', checking: false, errorMessage: ''
  };
  private listeners: Set<PublicNetworkListener> = new Set<PublicNetworkListener>();
  private networkConnection: connection.NetConnection | undefined = undefined;
  private generation: number = 0;
  private refreshTimer: number = -1;
  private refreshInFlight: boolean = false;

  private readonly availableHandler = (_handle: connection.NetHandle): void => this.refresh();
  private readonly propertiesHandler = (_info: connection.NetConnectionPropertyInfo): void => this.refresh();
  private readonly lostHandler = (_handle: connection.NetHandle): void => this.refresh();
  private readonly unavailableHandler = (): void => {
    this.generation += 1;
    this.snapshot = this.withStatus(false, '当前网络不可用');
    this.publish();
  };

  subscribe(listener: PublicNetworkListener): () => void {
    this.listeners.add(listener);
    listener(this.copySnapshot());
    if (this.listeners.size === 1) {
      this.start();
    }
    return (): void => {
      this.listeners.delete(listener);
      if (this.listeners.size === 0) {
        this.stop();
      }
    };
  }

  refresh(): void {
    if (this.listeners.size === 0) {
      return;
    }
    if (this.refreshInFlight) {
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
        this.refresh();
      }
    });
    // The first subscriber must not depend on a delayed network callback to see a result.
    this.beginRefresh();
  }

  private stop(): void {
    this.generation += 1;
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
    if (this.refreshInFlight) {
      return;
    }
    this.refreshInFlight = true;
    const generation = ++this.generation;
    hilog.info(NETWORK_LOG_DOMAIN, NETWORK_LOG_TAG, 'public network refresh started generation=%{public}d', generation);
    this.snapshot = this.withStatus(true, '');
    this.publish();
    this.resolvePublicNetwork().then((snapshot: PublicNetworkSnapshot): void => {
      if (!shouldApplyNetworkResult(generation, this.generation, this.listeners.size)) {
        return;
      }
      this.snapshot = snapshot;
      hilog.info(NETWORK_LOG_DOMAIN, NETWORK_LOG_TAG, 'public network refresh succeeded generation=%{public}d',
        generation);
      this.publish();
    }, (): void => {
      if (!shouldApplyNetworkResult(generation, this.generation, this.listeners.size)) {
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
  }

  private async resolvePublicNetwork(): Promise<PublicNetworkSnapshot> {
    const ipv4 = (await this.requestText(PUBLIC_IPV4_URL, 'text/plain')).trim();
    if (!isValidIpv4(ipv4)) {
      throw new Error('公网地址服务未返回有效 IPv4');
    }
    const geoJson = await this.requestText(`${GEOIP_BASE_URL}${ipv4}`, 'application/json');
    return parseGeoIpResponse(geoJson, ipv4);
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
      return response.result as string;
    } finally {
      if (timeoutId >= 0) {
        clearTimeout(timeoutId);
      }
      request.destroy();
    }
  }

  private withStatus(checking: boolean, errorMessage: string): PublicNetworkSnapshot {
    return {
      publicIpv4: this.snapshot.publicIpv4,
      country: this.snapshot.country,
      countryCode: this.snapshot.countryCode,
      checking: checking,
      lastSuccessAt: this.snapshot.lastSuccessAt,
      errorMessage: errorMessage
    };
  }

  private copySnapshot(): PublicNetworkSnapshot {
    return {
      publicIpv4: this.snapshot.publicIpv4,
      country: this.snapshot.country,
      countryCode: this.snapshot.countryCode,
      checking: this.snapshot.checking,
      lastSuccessAt: this.snapshot.lastSuccessAt,
      errorMessage: this.snapshot.errorMessage
    };
  }

  private publish(): void {
    const snapshot = this.copySnapshot();
    this.listeners.forEach((listener: PublicNetworkListener): void => listener(snapshot));
  }
}

export const publicNetworkService = new PublicNetworkService();
