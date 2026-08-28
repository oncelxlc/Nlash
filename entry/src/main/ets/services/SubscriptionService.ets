import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { Environment, fileIo, picker } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { Profile, ProfileType, ProfileUpdateStage } from '../models/ProfileModels';
import { profileRepository } from '../repository/ProfileRepository';
import { coreClient } from './CoreClient';

const PROFILE_DIRECTORY = 'profiles';
const MAX_PROFILE_BYTES = 5 * 1024 * 1024;
const HTTP_TIMEOUT_MS = 15000;
const DEFAULT_IMPORT_FILE_NAME = 'BygCloud.ymal';

export function buildDefaultImportPath(downloadDirectory: string): string {
  const separator = downloadDirectory.endsWith('/') ? '' : '/';
  return `${downloadDirectory}${separator}${DEFAULT_IMPORT_FILE_NAME}`;
}

export type ProfileStageListener = (stage: ProfileUpdateStage) => void;

class SubscriptionService {
  private context: common.UIAbilityContext | undefined;

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async importLocal(listener: ProfileStageListener): Promise<Profile> {
    const context = this.requireContext();
    const defaultPath = buildDefaultImportPath(Environment.getUserDownloadDir());
    let sourcePath = defaultPath;
    if (!this.safeAccess(defaultPath)) {
      const documentPicker = new picker.DocumentViewPicker(context);
      let selected: string[] = [];
      try {
        selected = await documentPicker.select({
          maxSelectNumber: 1,
          fileSuffixFilters: ['.yaml', '.yml', '.ymal']
        });
      } catch (error) {
        throw new Error('文件选择已取消或失败');
      }
      if (selected.length !== 1) {
        throw new Error('未选择 YAML 配置');
      }
      sourcePath = selected[0];
    }
    await this.ensureProfileDirectory();
    const id = util.generateRandomUUID();
    const targetPath = `${context.filesDir}/${PROFILE_DIRECTORY}/${id}.yaml`;
    const temporaryPath = `${targetPath}.tmp`;
    let source: fileIo.File | undefined;
    try {
      listener(ProfileUpdateStage.DOWNLOADING);
      source = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
      await fileIo.copyFile(source.fd, temporaryPath);
      const stat = await fileIo.stat(temporaryPath);
      if (stat.size <= 0) {
        throw new Error('所选配置为空');
      }
      if (stat.size > MAX_PROFILE_BYTES) {
        throw new Error('所选配置超过 5 MiB 限制');
      }
      listener(ProfileUpdateStage.DOWNLOADED);
      listener(ProfileUpdateStage.VALIDATING);
      await this.validateTemporaryFile(temporaryPath);
      listener(ProfileUpdateStage.APPLYING);
      await fileIo.rename(temporaryPath, targetPath);
      listener(ProfileUpdateStage.APPLIED);
      const now = Date.now();
      const profile: Profile = {
        id: id,
        name: `本地配置 ${new Date(now).toLocaleDateString()}`,
        type: ProfileType.LOCAL,
        sourceUrl: '',
        localPath: targetPath,
        createdAt: now,
        updatedAt: now,
        lastUpdateAt: now
      };
      listener(ProfileUpdateStage.PERSISTING);
      try {
        await profileRepository.save(profile);
      } catch (error) {
        await this.safeUnlink(targetPath);
        throw new Error('本地配置元数据保存失败');
      }
      listener(ProfileUpdateStage.SUCCESS);
      return profile;
    } catch (error) {
      await this.safeUnlink(temporaryPath);
      listener(ProfileUpdateStage.ERROR);
      throw this.toError(error, '导入本地配置失败');
    } finally {
      if (source !== undefined) {
        try {
          fileIo.closeSync(source.fd);
        } catch (error) {
        }
      }
    }
  }

  async add(name: string, sourceUrl: string, listener: ProfileStageListener): Promise<Profile> {
    const cleanName = this.validateName(name);
    const cleanSourceUrl = sourceUrl.trim();
    this.validateSourceUrl(cleanSourceUrl);
    const context = this.requireContext();
    await this.ensureProfileDirectory();
    const id = util.generateRandomUUID();
    const targetPath = `${context.filesDir}/${PROFILE_DIRECTORY}/${id}.yaml`;
    const temporaryPath = `${targetPath}.tmp`;

    try {
      listener(ProfileUpdateStage.DOWNLOADING);
      const content = await this.download(cleanSourceUrl);
      await this.writeFile(temporaryPath, content);
      listener(ProfileUpdateStage.DOWNLOADED);
      listener(ProfileUpdateStage.VALIDATING);
      await this.validateTemporaryFile(temporaryPath);
      listener(ProfileUpdateStage.APPLYING);
      await fileIo.rename(temporaryPath, targetPath);
      listener(ProfileUpdateStage.APPLIED);

      const now = Date.now();
      const profile: Profile = {
        id: id,
        name: cleanName,
        type: ProfileType.SUBSCRIPTION,
        sourceUrl: cleanSourceUrl,
        localPath: targetPath,
        createdAt: now,
        updatedAt: now,
        lastUpdateAt: now
      };
      listener(ProfileUpdateStage.PERSISTING);
      try {
        await profileRepository.save(profile);
      } catch (error) {
        await this.safeUnlink(targetPath);
        throw new Error('配置元数据保存失败');
      }
      listener(ProfileUpdateStage.SUCCESS);
      return profile;
    } catch (error) {
      await this.safeUnlink(temporaryPath);
      listener(ProfileUpdateStage.ERROR);
      throw this.toError(error, '添加配置失败');
    }
  }

  async update(profile: Profile, listener: ProfileStageListener): Promise<Profile> {
    if (profile.type !== ProfileType.SUBSCRIPTION || profile.sourceUrl.length === 0) {
      throw new Error('该配置不支持订阅更新');
    }
    this.validateSourceUrl(profile.sourceUrl);
    const temporaryPath = `${profile.localPath}.tmp`;
    const backupPath = `${profile.localPath}.bak`;
    let backupCreated = false;

    try {
      listener(ProfileUpdateStage.DOWNLOADING);
      const content = await this.download(profile.sourceUrl);
      await this.writeFile(temporaryPath, content);
      listener(ProfileUpdateStage.DOWNLOADED);
      listener(ProfileUpdateStage.VALIDATING);
      await this.validateTemporaryFile(temporaryPath);
      listener(ProfileUpdateStage.APPLYING);

      if (this.safeAccess(profile.localPath)) {
        await this.safeUnlink(backupPath);
        await fileIo.copyFile(profile.localPath, backupPath);
        backupCreated = true;
      }
      await fileIo.rename(temporaryPath, profile.localPath);
      listener(ProfileUpdateStage.APPLIED);

      const now = Date.now();
      const updated: Profile = {
        id: profile.id,
        name: profile.name,
        type: profile.type,
        sourceUrl: profile.sourceUrl,
        localPath: profile.localPath,
        createdAt: profile.createdAt,
        updatedAt: now,
        lastUpdateAt: now,
        expireAt: profile.expireAt,
        uploadBytes: profile.uploadBytes,
        downloadBytes: profile.downloadBytes,
        totalBytes: profile.totalBytes
      };
      listener(ProfileUpdateStage.PERSISTING);
      try {
        await profileRepository.save(updated);
      } catch (error) {
        if (backupCreated) {
          await this.safeUnlink(profile.localPath);
          await fileIo.rename(backupPath, profile.localPath);
        }
        throw new Error('更新后的配置元数据保存失败，已恢复旧配置');
      }
      await this.safeUnlink(backupPath);
      listener(ProfileUpdateStage.SUCCESS);
      return updated;
    } catch (error) {
      await this.safeUnlink(temporaryPath);
      listener(ProfileUpdateStage.ERROR);
      throw this.toError(error, '更新配置失败');
    }
  }

  async rename(profile: Profile, name: string): Promise<Profile> {
    const renamed: Profile = {
      id: profile.id,
      name: this.validateName(name),
      type: profile.type,
      sourceUrl: profile.sourceUrl,
      localPath: profile.localPath,
      createdAt: profile.createdAt,
      updatedAt: Date.now(),
      lastUpdateAt: profile.lastUpdateAt,
      expireAt: profile.expireAt,
      uploadBytes: profile.uploadBytes,
      downloadBytes: profile.downloadBytes,
      totalBytes: profile.totalBytes
    };
    await profileRepository.save(renamed);
    return renamed;
  }

  async remove(profile: Profile): Promise<void> {
    const tombstonePath = `${profile.localPath}.delete`;
    const hadFile = this.safeAccess(profile.localPath);
    if (hadFile) {
      await this.safeUnlink(tombstonePath);
      await fileIo.rename(profile.localPath, tombstonePath);
    }
    try {
      await profileRepository.remove(profile.id);
    } catch (error) {
      if (hadFile && this.safeAccess(tombstonePath)) {
        await fileIo.rename(tombstonePath, profile.localPath);
      }
      throw new Error('删除配置元数据失败');
    }
    await this.safeUnlink(tombstonePath);
    await this.safeUnlink(`${profile.localPath}.bak`);
    await this.safeUnlink(`${profile.localPath}.tmp`);
  }

  private async download(sourceUrl: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      let response: http.HttpResponse;
      try {
        response = await request.request(sourceUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          usingCache: false,
          connectTimeout: HTTP_TIMEOUT_MS,
          readTimeout: HTTP_TIMEOUT_MS,
          header: {
            'User-Agent': 'Nlash/1.0',
            'Accept': 'text/yaml,text/plain,application/yaml,application/octet-stream'
          }
        });
      } catch (error) {
        throw new Error('订阅下载失败，请检查网络和地址');
      }
      const status = Number(response.responseCode);
      if (status < 200 || status >= 300) {
        throw new Error(`订阅服务器返回 HTTP ${status}`);
      }
      if (response.resultType !== http.HttpDataType.ARRAY_BUFFER) {
        throw new Error('订阅服务器返回了不支持的数据类型');
      }
      const content = response.result as ArrayBuffer;
      if (content.byteLength === 0) {
        throw new Error('订阅内容为空');
      }
      if (content.byteLength > MAX_PROFILE_BYTES) {
        throw new Error('订阅内容超过 5 MiB 限制');
      }
      if (this.looksLikeHtml(content)) {
        throw new Error('订阅服务器返回了网页而不是 YAML');
      }
      return content;
    } finally {
      request.destroy();
    }
  }

  private async validateTemporaryFile(path: string): Promise<void> {
    const result = await coreClient.validateConfig(path);
    if (!result.ok) {
      const detail = result.message.trim();
      throw new Error(detail.length > 0 ?
        `Core 配置校验失败：${result.code} · ${detail}` : `Core 配置校验失败：${result.code}`);
    }
  }

  private async writeFile(path: string, content: ArrayBuffer): Promise<void> {
    const mode = fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC;
    const file = await fileIo.open(path, mode);
    try {
      const written = await fileIo.write(file.fd, content);
      if (written !== content.byteLength) {
        throw new Error('配置文件未完整写入');
      }
    } finally {
      fileIo.closeSync(file.fd);
    }
  }

  private looksLikeHtml(content: ArrayBuffer): boolean {
    const bytes = new Uint8Array(content);
    const length = Math.min(bytes.length, 256);
    let prefix = '';
    for (let index = 0; index < length; index += 1) {
      prefix += String.fromCharCode(bytes[index]);
    }
    const normalized = prefix.trim().toLowerCase();
    return normalized.startsWith('<!doctype html') || normalized.startsWith('<html') ||
      normalized.includes('<body');
  }

  private validateSourceUrl(sourceUrl: string): void {
    const normalized = sourceUrl.trim().toLowerCase();
    if (!normalized.startsWith('https://') && !normalized.startsWith('http://')) {
      throw new Error('订阅地址必须使用 HTTP 或 HTTPS');
    }
    const schemeEnd = normalized.indexOf('://') + 3;
    let authorityEnd = sourceUrl.indexOf('/', schemeEnd);
    if (authorityEnd < 0) {
      authorityEnd = sourceUrl.length;
    }
    const authority = sourceUrl.substring(schemeEnd, authorityEnd);
    if (sourceUrl.length > 2048 || schemeEnd < 3 || authority.length === 0 || authority.includes(' ')) {
      throw new Error('订阅地址格式无效');
    }
  }

  private validateName(name: string): string {
    const cleanName = name.trim();
    if (cleanName.length === 0 || cleanName.length > 64) {
      throw new Error('配置名称长度必须为 1–64 个字符');
    }
    return cleanName;
  }

  private async ensureProfileDirectory(): Promise<void> {
    const context = this.requireContext();
    const directory = `${context.filesDir}/${PROFILE_DIRECTORY}`;
    if (!this.safeAccess(directory)) {
      await fileIo.mkdir(directory, true);
    }
  }

  private safeAccess(path: string): boolean {
    try {
      return fileIo.accessSync(path);
    } catch (error) {
      return false;
    }
  }

  private async safeUnlink(path: string): Promise<void> {
    if (!this.safeAccess(path)) {
      return;
    }
    try {
      await fileIo.unlink(path);
    } catch (error) {
    }
  }

  private toError(error: Object, fallback: string): Error {
    const exception = error as Error;
    const message = typeof exception.message === 'string' ? exception.message : '';
    return message.length > 0 ? new Error(message) : new Error(fallback);
  }

  private requireContext(): common.UIAbilityContext {
    if (this.context === undefined) {
      throw new Error('订阅服务尚未初始化');
    }
    return this.context;
  }
}

export const subscriptionService = new SubscriptionService();
