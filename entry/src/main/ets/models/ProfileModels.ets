export enum ProfileType {
  SUBSCRIPTION = 'SUBSCRIPTION',
  LOCAL = 'LOCAL'
}

export enum ProfileUpdateStage {
  IDLE = 'IDLE',
  DOWNLOADING = 'DOWNLOADING',
  DOWNLOADED = 'DOWNLOADED',
  VALIDATING = 'VALIDATING',
  APPLYING = 'APPLYING',
  APPLIED = 'APPLIED',
  PERSISTING = 'PERSISTING',
  SUCCESS = 'SUCCESS',
  ERROR = 'ERROR'
}

export const DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES: number = 1440;
export const MIN_PROFILE_UPDATE_INTERVAL_MINUTES: number = 15;
export const MAX_PROFILE_UPDATE_INTERVAL_MINUTES: number = 10080;

export interface Profile {
  id: string;
  name: string;
  type: ProfileType;
  sourceUrl: string;
  localPath: string;
  createdAt: number;
  updatedAt: number;
  lastUpdateAt?: number;
  expireAt?: number;
  uploadBytes?: number;
  downloadBytes?: number;
  totalBytes?: number;
  autoUpdateEnabled: boolean;
  updateIntervalMinutes: number;
}

export interface ProfileEditDraft {
  name: string;
  sourceUrl: string;
  autoUpdateEnabled: boolean;
  updateIntervalMinutes: number;
}

export interface ProfileStoreSnapshot {
  profiles: Profile[];
  activeProfileId: string;
  stage: ProfileUpdateStage;
  busyProfileId: string;
}

export type ProfileStoreListener = (snapshot: ProfileStoreSnapshot) => void;

export function normalizeProfileUpdateInterval(value: number): number {
  if (!Number.isFinite(value)) {
    return DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES;
  }
  const rounded = Math.round(value);
  return Math.min(MAX_PROFILE_UPDATE_INTERVAL_MINUTES,
    Math.max(MIN_PROFILE_UPDATE_INTERVAL_MINUTES, rounded));
}

export function isProfileUpdateDue(profile: Profile, now: number): boolean {
  if (profile.type !== ProfileType.SUBSCRIPTION || !profile.autoUpdateEnabled) {
    return false;
  }
  const lastUpdateAt = profile.lastUpdateAt ?? profile.createdAt;
  return now >= lastUpdateAt + normalizeProfileUpdateInterval(profile.updateIntervalMinutes) * 60 * 1000;
}

export function profileUsageRatio(profile: Profile): number {
  const total = profile.totalBytes ?? 0;
  if (total <= 0) {
    return 0;
  }
  const used = Math.max(0, (profile.uploadBytes ?? 0) + (profile.downloadBytes ?? 0));
  return Math.min(1, used / total);
}

export function formatProfileRelativeTime(timestamp: number | undefined, now: number = Date.now()): string {
  if (timestamp === undefined || timestamp <= 0) {
    return '尚未更新';
  }
  const elapsedMinutes = Math.max(0, Math.floor((now - timestamp) / 60000));
  if (elapsedMinutes < 1) {
    return '刚刚';
  }
  if (elapsedMinutes < 60) {
    return `${elapsedMinutes} 分钟前`;
  }
  const elapsedHours = Math.floor(elapsedMinutes / 60);
  if (elapsedHours < 24) {
    return `${elapsedHours} 小时前`;
  }
  const elapsedDays = Math.floor(elapsedHours / 24);
  if (elapsedDays < 30) {
    return `${elapsedDays} 天前`;
  }
  return new Date(timestamp).toLocaleDateString();
}

export function getSubscriptionHost(sourceUrl: string): string {
  const schemeSeparator = sourceUrl.indexOf('://');
  if (schemeSeparator < 0) {
    return '订阅地址';
  }
  const authorityStart = schemeSeparator + 3;
  let authorityEnd = sourceUrl.length;
  const delimiters: string[] = ['/', '?', '#'];
  delimiters.forEach((delimiter: string): void => {
    const index = sourceUrl.indexOf(delimiter, authorityStart);
    if (index >= 0 && index < authorityEnd) {
      authorityEnd = index;
    }
  });
  let authority = sourceUrl.substring(authorityStart, authorityEnd);
  const credentialsEnd = authority.lastIndexOf('@');
  if (credentialsEnd >= 0) {
    authority = authority.substring(credentialsEnd + 1);
  }
  return authority.length > 0 ? authority : '订阅地址';
}
