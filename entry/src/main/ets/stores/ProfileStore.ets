import { common } from '@kit.AbilityKit';
import {
  isProfileUpdateDue,
  Profile,
  ProfileEditDraft,
  ProfileStoreListener,
  ProfileStoreSnapshot,
  ProfileType,
  ProfileUpdateStage
} from '../models/ProfileModels';
import { FeedbackLevel } from '../models/FeedbackModels';
import { VpnState } from '../models/VpnModels';
import { preferenceRepository } from '../repository/PreferenceRepository';
import { profileRepository } from '../repository/ProfileRepository';
import { subscriptionService } from '../services/SubscriptionService';
import { feedbackService } from '../services/FeedbackService';
import { vpnService } from '../services/VpnService';

class ProfileStore {
  private readonly autoUpdateTickMs: number = 60 * 1000;
  private readonly autoUpdateRetryMs: number = 15 * 60 * 1000;
  private profiles: Profile[] = [];
  private activeProfileId: string = '';
  private stage: ProfileUpdateStage = ProfileUpdateStage.IDLE;
  private busyProfileId: string = '';
  private listeners: Set<ProfileStoreListener> = new Set<ProfileStoreListener>();
  private initializeOperation: Promise<void> | undefined;
  private initialized: boolean = false;
  private autoUpdateTimer: number = -1;
  private autoUpdateRunning: boolean = false;
  private autoUpdateRetryAt: Map<string, number> = new Map<string, number>();
  private vpnUnsubscribe: (() => void) | undefined = undefined;

  initialize(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) {
      this.startAutoUpdateScheduler();
      this.subscribeVpnState();
      return Promise.resolve();
    }
    if (this.initializeOperation === undefined) {
      subscriptionService.initialize(context);
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

  getSnapshot(): ProfileStoreSnapshot {
    return {
      profiles: this.profiles.slice(),
      activeProfileId: this.activeProfileId,
      stage: this.stage,
      busyProfileId: this.busyProfileId
    };
  }

  subscribe(listener: ProfileStoreListener): () => void {
    this.listeners.add(listener);
    listener(this.getSnapshot());
    return (): void => {
      this.listeners.delete(listener);
    };
  }

  onForeground(): void {
    this.runDueAutoUpdates();
  }

  shutdown(): void {
    if (this.autoUpdateTimer >= 0) {
      clearInterval(this.autoUpdateTimer);
      this.autoUpdateTimer = -1;
    }
    this.vpnUnsubscribe?.();
    this.vpnUnsubscribe = undefined;
  }

  async addSubscription(name: string, sourceUrl: string): Promise<void> {
    await this.ensureReady();
    this.assertIdle();
    this.beginOperation('new');
    try {
      const profile = await subscriptionService.add(name, sourceUrl, (stage: ProfileUpdateStage): void => {
        this.setStage(stage);
      });
      await this.reload();
      if (this.activeProfileId.length === 0) {
        await this.activate(profile);
      }
      this.finishOperation('配置已添加并通过校验');
    } catch (error) {
      const failure = this.toError(error);
      this.failOperation(failure.message);
      throw failure;
    }
  }

  async importLocal(): Promise<void> {
    await this.ensureReady();
    this.assertIdle();
    this.beginOperation('import');
    try {
      const profile = await subscriptionService.importLocal((stage: ProfileUpdateStage): void => {
        this.setStage(stage);
      });
      await this.reload();
      if (this.activeProfileId.length === 0) {
        await this.activate(profile);
      }
      this.finishOperation('本地配置已导入并通过校验');
    } catch (error) {
      const failure = this.toError(error);
      this.failOperation(failure.message);
      throw failure;
    }
  }

  async update(id: string): Promise<void> {
    await this.ensureReady();
    this.assertIdle();
    this.assertRuntimeAllowsProfileChange(id);
    const profile = this.requireProfile(id);
    this.beginOperation(id);
    try {
      await subscriptionService.update(profile, (stage: ProfileUpdateStage): void => {
        this.setStage(stage);
      });
      await this.reload();
      this.finishOperation('订阅已更新并通过校验');
    } catch (error) {
      const failure = this.toError(error);
      this.failOperation(failure.message);
      throw failure;
    }
  }

  async saveAndUpdate(id: string, draft: ProfileEditDraft): Promise<void> {
    await this.ensureReady();
    this.assertIdle();
    this.assertRuntimeAllowsProfileChange(id);
    const profile = this.requireProfile(id);
    this.beginOperation(id);
    try {
      if (profile.type === ProfileType.LOCAL) {
        await subscriptionService.rename(profile, draft.name);
      } else {
        await subscriptionService.editAndUpdate(profile, draft, (stage: ProfileUpdateStage): void => {
          this.setStage(stage);
        });
      }
      await this.reload();
      this.autoUpdateRetryAt.delete(id);
      this.finishOperation(profile.type === ProfileType.LOCAL ? '配置已重命名' : '配置已保存并更新');
    } catch (error) {
      const failure = this.toError(error);
      this.failOperation(failure.message);
      throw failure;
    }
  }

  async updateAll(): Promise<void> {
    await this.ensureReady();
    this.assertIdle();
    this.assertRuntimeStopped();
    const subscriptions = this.profiles.filter((profile: Profile): boolean =>
      profile.type === ProfileType.SUBSCRIPTION);
    if (subscriptions.length === 0) {
      return;
    }
    for (let index = 0; index < subscriptions.length; index += 1) {
      await this.update(subscriptions[index].id);
    }
  }

  async rename(id: string, name: string): Promise<void> {
    await this.ensureReady();
    this.assertIdle();
    const profile = this.requireProfile(id);
    this.beginOperation(id);
    try {
      await subscriptionService.rename(profile, name);
      await this.reload();
      this.finishOperation('配置已重命名');
    } catch (error) {
      const failure = this.toError(error);
      this.failOperation(failure.message);
      throw failure;
    }
  }

  async select(id: string): Promise<void> {
    await this.ensureReady();
    this.assertIdle();
    this.assertRuntimeStopped();
    const profile = this.requireProfile(id);
    this.beginOperation(id);
    try {
      await this.activate(profile);
      this.finishOperation('已切换活动配置');
    } catch (error) {
      const failure = this.toError(error);
      this.failOperation(failure.message);
      throw failure;
    }
  }

  async remove(id: string): Promise<void> {
    await this.ensureReady();
    this.assertIdle();
    this.assertRuntimeAllowsProfileChange(id);
    const profile = this.requireProfile(id);
    this.beginOperation(id);
    try {
      await subscriptionService.remove(profile);
      if (this.activeProfileId === id) {
        await preferenceRepository.clearActiveProfile();
        this.activeProfileId = '';
      }
      await preferenceRepository.removeProxySelections(id);
      this.autoUpdateRetryAt.delete(id);
      await this.reload();
      if (this.activeProfileId.length === 0 && this.profiles.length > 0) {
        await this.activate(this.profiles[0]);
      }
      this.finishOperation('配置已删除');
    } catch (error) {
      const failure = this.toError(error);
      this.failOperation(failure.message);
      throw failure;
    }
  }

  private async initializeInternal(context: common.UIAbilityContext): Promise<void> {
    await preferenceRepository.initialize(context);
    await profileRepository.initialize(context);
    this.profiles = await profileRepository.list();
    this.activeProfileId = await preferenceRepository.getActiveProfileId();
    if (this.activeProfileId.length > 0 && !this.profiles.some((profile: Profile): boolean =>
      profile.id === this.activeProfileId)) {
      await preferenceRepository.clearActiveProfile();
      this.activeProfileId = '';
    } else if (this.activeProfileId.length > 0) {
      const activeProfile = this.profiles.find((profile: Profile): boolean => profile.id === this.activeProfileId);
      if (activeProfile !== undefined &&
        await preferenceRepository.getActiveProfilePath() !== activeProfile.localPath) {
        await preferenceRepository.setActiveProfile(activeProfile.id, activeProfile.localPath);
      }
    }
    this.initialized = true;
    this.publish();
    this.startAutoUpdateScheduler();
    this.subscribeVpnState();
  }

  private subscribeVpnState(): void {
    if (this.vpnUnsubscribe !== undefined) {
      return;
    }
    this.vpnUnsubscribe = vpnService.subscribe((state: VpnState): void => {
      if (state === VpnState.IDLE || state === VpnState.DISCONNECTED || state === VpnState.ERROR) {
        this.runDueAutoUpdates();
      }
    });
  }

  private async reload(): Promise<void> {
    this.profiles = await profileRepository.list();
    this.publish();
  }

  private async activate(profile: Profile): Promise<void> {
    await preferenceRepository.setActiveProfile(profile.id, profile.localPath);
    this.activeProfileId = profile.id;
    this.publish();
  }

  private assertRuntimeAllowsProfileChange(id: string): void {
    if (id !== this.activeProfileId) {
      return;
    }
    if (this.isRuntimeActive()) {
      throw new Error('请先断开 VPN，再修改当前活动配置');
    }
  }

  private assertRuntimeStopped(): void {
    if (this.isRuntimeActive()) {
      throw new Error('请先断开 VPN，再切换或批量更新配置');
    }
  }

  private isRuntimeActive(): boolean {
    const state = vpnService.getState();
    return state === VpnState.CONNECTED || state === VpnState.STARTING ||
      state === VpnState.REQUESTING_PERMISSION || state === VpnState.STOPPING;
  }

  private startAutoUpdateScheduler(): void {
    if (this.autoUpdateTimer < 0) {
      this.autoUpdateTimer = setInterval((): void => {
        this.runDueAutoUpdates();
      }, this.autoUpdateTickMs);
    }
    this.runDueAutoUpdates();
  }

  private runDueAutoUpdates(): void {
    if (!this.initialized || this.autoUpdateRunning || this.busyProfileId.length > 0) {
      return;
    }
    this.autoUpdateRunning = true;
    this.runDueAutoUpdatesInternal().then((): void => {
      this.autoUpdateRunning = false;
    }, (): void => {
      this.autoUpdateRunning = false;
    });
  }

  private async runDueAutoUpdatesInternal(): Promise<void> {
    const now = Date.now();
    const dueProfiles = this.profiles.filter((profile: Profile): boolean => {
      const retryAt = this.autoUpdateRetryAt.get(profile.id) ?? 0;
      return isProfileUpdateDue(profile, now) && now >= retryAt &&
        !(profile.id === this.activeProfileId && this.isRuntimeActive());
    });
    let failureCount = 0;
    for (let index = 0; index < dueProfiles.length; index += 1) {
      if (this.busyProfileId.length > 0) {
        break;
      }
      const profile = dueProfiles[index];
      try {
        await this.update(profile.id);
        this.autoUpdateRetryAt.delete(profile.id);
      } catch (error) {
        this.autoUpdateRetryAt.set(profile.id, Date.now() + this.autoUpdateRetryMs);
        failureCount += 1;
      }
    }
    if (failureCount > 0) {
      feedbackService.publishDeduplicated(FeedbackLevel.WARNING,
        `${failureCount} 个订阅自动更新失败，将稍后重试`, this.autoUpdateRetryMs);
    }
  }

  private requireProfile(id: string): Profile {
    const profile = this.profiles.find((item: Profile): boolean => item.id === id);
    if (profile === undefined) {
      throw new Error('配置不存在或已被删除');
    }
    return profile;
  }

  private async ensureReady(): Promise<void> {
    if (this.initializeOperation !== undefined) {
      await this.initializeOperation;
    }
    if (!this.initialized) {
      throw new Error('配置数据初始化失败');
    }
  }

  private assertIdle(): void {
    if (this.busyProfileId.length > 0) {
      throw new Error('已有配置操作正在进行');
    }
  }

  private beginOperation(profileId: string): void {
    this.busyProfileId = profileId;
    this.stage = ProfileUpdateStage.IDLE;
    this.publish();
  }

  private setStage(stage: ProfileUpdateStage): void {
    this.stage = stage;
    this.publish();
  }

  private finishOperation(_message: string): void {
    this.stage = ProfileUpdateStage.SUCCESS;
    this.busyProfileId = '';
    this.publish();
  }

  private failOperation(_message: string): void {
    this.stage = ProfileUpdateStage.ERROR;
    this.busyProfileId = '';
    this.publish();
  }

  private publish(): void {
    const snapshot = this.getSnapshot();
    this.listeners.forEach((listener: ProfileStoreListener): void => {
      listener(snapshot);
    });
  }

  private toError(error: Object): Error {
    const exception = error as Error;
    const message = typeof exception.message === 'string' ? exception.message : '';
    return message.length > 0 ? new Error(message) : new Error('配置操作失败');
  }
}

export const profileStore = new ProfileStore();
