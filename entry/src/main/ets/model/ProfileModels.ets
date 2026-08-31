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
