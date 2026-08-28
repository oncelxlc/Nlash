import { BusinessError } from '@kit.BasicServicesKit';
import { connection } from '@kit.NetworkKit';
import { LocalNetworkSnapshot } from '../models/RuntimeModels';

export type LocalNetworkListener = (snapshot: LocalNetworkSnapshot) => void;

export function shouldApplyNetworkResult(resultGeneration: number, currentGeneration: number,
  listenerCount: number): boolean {
  return resultGeneration === currentGeneration && listenerCount > 0;
}

export function selectLocalIpv4(addresses: string[]): string {
  const candidates = addresses.filter((address: string): boolean => {
    const parts = address.split('.');
    if (parts.length !== 4 || address === '0.0.0.0' || address.startsWith('127.') ||
      address === '172.19.0.1') {
      return false;
    }
    return parts.every((part: string): boolean => {
      const value = Number(part);
      return Number.isInteger(value) && value >= 0 && value <= 255;
    });
  });
  const privateAddress = candidates.find((address: string): boolean =>
    address.startsWith('10.') || address.startsWith('192.168.') ||
      /^172\.(1[6-9]|2\d|3[01])\./.test(address));
  return privateAddress ?? candidates[0] ?? '未知';
}

class LocalNetworkService {
  private snapshot: LocalNetworkSnapshot = { localIpv4: '未知', checking: false };
  private listeners: Set<LocalNetworkListener> = new Set<LocalNetworkListener>();
  private networkConnection: connection.NetConnection | undefined = undefined;
  private generation: number = 0;

  private readonly availableHandler = (_handle: connection.NetHandle): void => {
    this.refresh();
  };

  private readonly propertiesHandler = (_info: connection.NetConnectionPropertyInfo): void => {
    this.refresh();
  };

  private readonly lostHandler = (_handle: connection.NetHandle): void => {
    this.refresh();
  };

  private readonly unavailableHandler = (): void => {
    this.generation += 1;
    this.snapshot = { localIpv4: '未知', checking: false };
    this.publish();
  };

  subscribe(listener: LocalNetworkListener): () => void {
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
        this.unavailableHandler();
      } else {
        this.refresh();
      }
    });
    this.refresh();
  }

  private stop(): void {
    this.generation += 1;
    const monitor = this.networkConnection;
    this.networkConnection = undefined;
    if (monitor === undefined) {
      return;
    }
    monitor.unregister((_error: BusinessError): void => {
    });
  }

  private refresh(): void {
    const generation = ++this.generation;
    this.snapshot = { localIpv4: this.snapshot.localIpv4, checking: true };
    this.publish();
    this.resolveLocalIpv4().then((localIpv4: string): void => {
      if (!shouldApplyNetworkResult(generation, this.generation, this.listeners.size)) {
        return;
      }
      this.snapshot = { localIpv4: localIpv4, checking: false };
      this.publish();
    }, (): void => {
      if (!shouldApplyNetworkResult(generation, this.generation, this.listeners.size)) {
        return;
      }
      this.snapshot = { localIpv4: '未知', checking: false };
      this.publish();
    });
  }

  private async resolveLocalIpv4(): Promise<string> {
    const addresses: string[] = [];
    const nets = await connection.getAllNets();
    for (let index = 0; index < nets.length; index += 1) {
      const properties = await connection.getConnectionProperties(nets[index]);
      properties.linkAddresses.forEach((linkAddress): void => {
        if (linkAddress.address.family === 1) {
          addresses.push(linkAddress.address.address);
        }
      });
    }
    return selectLocalIpv4(addresses);
  }

  private copySnapshot(): LocalNetworkSnapshot {
    return {
      localIpv4: this.snapshot.localIpv4,
      checking: this.snapshot.checking
    };
  }

  private publish(): void {
    const snapshot = this.copySnapshot();
    this.listeners.forEach((listener: LocalNetworkListener): void => listener(snapshot));
  }
}

export const localNetworkService = new LocalNetworkService();
