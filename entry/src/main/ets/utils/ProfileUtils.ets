import { ProfileType, Profile } from '../model/ProfileModels';
import {
  DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES,
  MIN_PROFILE_UPDATE_INTERVAL_MINUTES,
  MAX_PROFILE_UPDATE_INTERVAL_MINUTES
} from '../constants/ProfileConstants';

/** 保存顺序优先，未记录配置按创建时间和 ID 稳定排序，不修改传入数组。 */
export function orderProfiles(profiles: Profile[], ids: string[]): Profile[] {
  const positions = new Map<string, number>();
  ids.forEach((id: string, index: number): void => {
    if (!positions.has(id)) {
      positions.set(id, index);
    }
  });
  return profiles.slice().sort((left: Profile, right: Profile): number =>
    (positions.get(left.id) ?? ids.length) - (positions.get(right.id) ?? ids.length) ||
    right.createdAt - left.createdAt || left.id.localeCompare(right.id));
}

export function moveProfile(profiles: Profile[], from: number, to: number): Profile[] {
  const result = profiles.slice();
  if (!Number.isInteger(from) || !Number.isInteger(to) || from < 0 || from >= result.length ||
    to < 0 || to >= result.length || from === to) {
    return result;
  }
  const moved = result.splice(from, 1)[0];
  result.splice(to, 0, moved);
  return result;
}

export function normalizeProfileUpdateInterval(value: number): number {
  if (!Number.isFinite(value)) {
    return DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES;
  }
  const rounded = Math.round(value);
  return Math.min(MAX_PROFILE_UPDATE_INTERVAL_MINUTES,
    Math.max(MIN_PROFILE_UPDATE_INTERVAL_MINUTES, rounded));
}

/** 仅订阅参与自动更新，首次更新前以创建时间为基准，间隔单位为分钟。 */
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

export function formatProfileBytes(value: number): string {
  if (value < 1024) {
    return `${value}B`;
  }
  const units: string[] = ['KB', 'MB', 'GB', 'TB'];
  let converted = value / 1024;
  let unitIndex = 0;
  while (converted >= 1024 && unitIndex < units.length - 1) {
    converted /= 1024;
    unitIndex += 1;
  }
  return `${Number(converted.toFixed(1))}${units[unitIndex]}`;
}

/** 使用本地日期，避免 UTC 转换使到期日偏移一天。 */
export function formatProfileExpiry(timestamp: number): string {
  const date = new Date(timestamp);
  if (timestamp <= 0 || !Number.isFinite(date.getTime())) {
    return '';
  }
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-` +
    String(date.getDate()).padStart(2, '0');
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

/** 只展示主机与端口，去掉用户凭据、路径、查询参数及片段中的潜在订阅令牌。 */
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
