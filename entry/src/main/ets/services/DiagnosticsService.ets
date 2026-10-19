import { DnsQueryRecord, GeoResourceSnapshot, GeoSettingsPatch } from '../model/DiagnosticsModels';
import { runtimeControlService } from './RuntimeControlService';

/** 复用现有跨进程命令通道，数据仍由 Core 持有。 */
class DiagnosticsService {
  async dnsQueries(): Promise<DnsQueryRecord[]> {
    const response = await runtimeControlService.execute<DnsQueryRecord[]>('dnsSnapshot');
    if (!response.ok || response.data === undefined) { throw new Error(response.message || '读取 DNS 查询失败'); }
    return response.data;
  }

  async resources(): Promise<GeoResourceSnapshot> {
    const response = await runtimeControlService.execute<GeoResourceSnapshot>('resourceSnapshot');
    if (!response.ok || response.data === undefined) { throw new Error(response.message || '读取资源失败'); }
    return response.data;
  }

  async saveResources(patch: GeoSettingsPatch): Promise<GeoResourceSnapshot> {
    const response = await runtimeControlService.execute<GeoResourceSnapshot>('saveGeoSettings', patch);
    if (!response.ok || response.data === undefined) { throw new Error(response.message || '保存资源设置失败'); }
    return response.data;
  }

  async updateResources(): Promise<void> {
    const response = await runtimeControlService.execute<Object>('updateGeoResources', undefined, 105000);
    if (!response.ok) { throw new Error(response.message || '资源更新失败，请重试'); }
  }
}

export const diagnosticsService = new DiagnosticsService();
