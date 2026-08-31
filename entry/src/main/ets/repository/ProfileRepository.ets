import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES } from '../constants/ProfileConstants';
import { Profile, ProfileType } from '../model/ProfileModels';

const DATABASE_NAME = 'nlash.db';
const PROFILE_TABLE = 'profiles';
const CREATE_PROFILE_TABLE = `CREATE TABLE IF NOT EXISTS ${PROFILE_TABLE} (
  id TEXT PRIMARY KEY NOT NULL,
  name TEXT NOT NULL,
  type TEXT NOT NULL,
  source_url TEXT,
  local_path TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  last_update_at INTEGER,
  expire_at INTEGER,
  upload_bytes INTEGER,
  download_bytes INTEGER,
  total_bytes INTEGER,
  auto_update_enabled INTEGER NOT NULL DEFAULT 0,
  update_interval_minutes INTEGER NOT NULL DEFAULT ${DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES}
)`;

const PROFILE_COLUMN_AUTO_UPDATE = 'auto_update_enabled';
const PROFILE_COLUMN_UPDATE_INTERVAL = 'update_interval_minutes';

class ProfileRepository {
  private store: relationalStore.RdbStore | undefined;
  private initializeOperation: Promise<void> | undefined;

  initialize(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return Promise.resolve();
    }
    if (this.initializeOperation === undefined) {
      const operation = this.initializeInternal(context);
      this.initializeOperation = operation;
      operation.then((): void => {
        this.initializeOperation = undefined;
      }, (): void => {
        this.initializeOperation = undefined;
      });
    }
    return this.initializeOperation;
  }

  async list(): Promise<Profile[]> {
    const predicates = new relationalStore.RdbPredicates(PROFILE_TABLE);
    predicates.orderByDesc('updated_at');
    const result = await this.requireStore().query(predicates);
    const profiles: Profile[] = [];
    try {
      while (result.goToNextRow()) {
        profiles.push(this.readProfile(result));
      }
    } finally {
      result.close();
    }
    return profiles;
  }

  async get(id: string): Promise<Profile | undefined> {
    const predicates = new relationalStore.RdbPredicates(PROFILE_TABLE);
    predicates.equalTo('id', id);
    const result = await this.requireStore().query(predicates);
    try {
      if (!result.goToFirstRow()) {
        return undefined;
      }
      return this.readProfile(result);
    } finally {
      result.close();
    }
  }

  async save(profile: Profile): Promise<void> {
    await this.requireStore().insert(PROFILE_TABLE, this.toValuesBucket(profile),
      relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  async remove(id: string): Promise<void> {
    const predicates = new relationalStore.RdbPredicates(PROFILE_TABLE);
    predicates.equalTo('id', id);
    await this.requireStore().delete(predicates);
  }

  private async initializeInternal(context: common.Context): Promise<void> {
    const store = await relationalStore.getRdbStore(context, {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S2
    });
    await store.executeSql(CREATE_PROFILE_TABLE);
    await this.migrateProfileTable(store);
    this.store = store;
  }

  private async migrateProfileTable(store: relationalStore.RdbStore): Promise<void> {
    const result = await store.querySql(`PRAGMA table_info(${PROFILE_TABLE})`);
    const columns = new Set<string>();
    try {
      while (result.goToNextRow()) {
        columns.add(result.getString(result.getColumnIndex('name')));
      }
    } finally {
      result.close();
    }
    if (!columns.has(PROFILE_COLUMN_AUTO_UPDATE)) {
      await store.executeSql(
        `ALTER TABLE ${PROFILE_TABLE} ADD COLUMN ${PROFILE_COLUMN_AUTO_UPDATE} INTEGER NOT NULL DEFAULT 0`);
    }
    if (!columns.has(PROFILE_COLUMN_UPDATE_INTERVAL)) {
      await store.executeSql(
        `ALTER TABLE ${PROFILE_TABLE} ADD COLUMN ${PROFILE_COLUMN_UPDATE_INTERVAL} INTEGER NOT NULL ` +
          `DEFAULT ${DEFAULT_PROFILE_UPDATE_INTERVAL_MINUTES}`);
    }
  }

  private readProfile(result: relationalStore.ResultSet): Profile {
    const profile: Profile = {
      id: result.getString(result.getColumnIndex('id')),
      name: result.getString(result.getColumnIndex('name')),
      type: this.parseType(result.getString(result.getColumnIndex('type'))),
      sourceUrl: this.readNullableString(result, 'source_url'),
      localPath: result.getString(result.getColumnIndex('local_path')),
      createdAt: result.getLong(result.getColumnIndex('created_at')),
      updatedAt: result.getLong(result.getColumnIndex('updated_at')),
      autoUpdateEnabled: result.getLong(result.getColumnIndex(PROFILE_COLUMN_AUTO_UPDATE)) === 1,
      updateIntervalMinutes: result.getLong(result.getColumnIndex(PROFILE_COLUMN_UPDATE_INTERVAL))
    };
    this.assignOptionalNumber(result, 'last_update_at', (value: number): void => {
      profile.lastUpdateAt = value;
    });
    this.assignOptionalNumber(result, 'expire_at', (value: number): void => {
      profile.expireAt = value;
    });
    this.assignOptionalNumber(result, 'upload_bytes', (value: number): void => {
      profile.uploadBytes = value;
    });
    this.assignOptionalNumber(result, 'download_bytes', (value: number): void => {
      profile.downloadBytes = value;
    });
    this.assignOptionalNumber(result, 'total_bytes', (value: number): void => {
      profile.totalBytes = value;
    });
    return profile;
  }

  private toValuesBucket(profile: Profile): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      id: profile.id,
      name: profile.name,
      type: profile.type,
      source_url: profile.sourceUrl,
      local_path: profile.localPath,
      created_at: profile.createdAt,
      updated_at: profile.updatedAt,
      auto_update_enabled: profile.autoUpdateEnabled ? 1 : 0,
      update_interval_minutes: profile.updateIntervalMinutes
    };
    if (profile.lastUpdateAt !== undefined) {
      values.last_update_at = profile.lastUpdateAt;
    }
    if (profile.expireAt !== undefined) {
      values.expire_at = profile.expireAt;
    }
    if (profile.uploadBytes !== undefined) {
      values.upload_bytes = profile.uploadBytes;
    }
    if (profile.downloadBytes !== undefined) {
      values.download_bytes = profile.downloadBytes;
    }
    if (profile.totalBytes !== undefined) {
      values.total_bytes = profile.totalBytes;
    }
    return values;
  }

  private readNullableString(result: relationalStore.ResultSet, column: string): string {
    const index = result.getColumnIndex(column);
    return result.isColumnNull(index) ? '' : result.getString(index);
  }

  private assignOptionalNumber(result: relationalStore.ResultSet, column: string,
    assign: (value: number) => void): void {
    const index = result.getColumnIndex(column);
    if (!result.isColumnNull(index)) {
      assign(result.getLong(index));
    }
  }

  private parseType(value: string): ProfileType {
    return value === ProfileType.LOCAL ? ProfileType.LOCAL : ProfileType.SUBSCRIPTION;
  }

  private requireStore(): relationalStore.RdbStore {
    if (this.store === undefined) {
      throw new Error('Profile 数据库尚未初始化');
    }
    return this.store;
  }
}

export const profileRepository = new ProfileRepository();
