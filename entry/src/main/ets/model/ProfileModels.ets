export enum ProfileType {
  SUBSCRIPTION = 'SUBSCRIPTION',
  LOCAL = 'LOCAL'
}

/** 文件导入或订阅更新阶段；APPLIED 表示正式文件已替换，后续仍需保存元数据。 */
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

/** 配置元数据：时间为 Unix 毫秒，流量为字节；可选字段缺失表示订阅未提供。 */
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

/** 编辑面板的待保存值，与已持久化 Profile 分开，允许用户取消编辑。 */
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
