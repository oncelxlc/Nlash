export interface DnsQueryRecord {
  id: string;
  host: string;
  type: string;
  answers: string[];
  initiator: string;
  upstream: string;
  cached: boolean;
  start: number;
  duration: number;
  error: string;
}

export interface GeoResource {
  kind: string;
  url: string;
  size: number;
  updatedAt: number;
}

export interface GeoResourceSnapshot {
  resources: GeoResource[];
  autoUpdate: boolean;
  intervalHours: number;
  updating: boolean;
}

export interface GeoSettingsPatch {
  urls?: Record<string, string>;
  autoUpdate?: boolean;
  intervalHours?: number;
}
