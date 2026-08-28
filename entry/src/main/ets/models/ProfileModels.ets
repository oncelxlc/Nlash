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
}

export interface ProfileStoreSnapshot {
  profiles: Profile[];
  activeProfileId: string;
  stage: ProfileUpdateStage;
  busyProfileId: string;
}

export type ProfileStoreListener = (snapshot: ProfileStoreSnapshot) => void;

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
