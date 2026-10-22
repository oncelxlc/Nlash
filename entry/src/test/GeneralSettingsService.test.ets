import { ArgumentMatchers, describe, expect, it, MockKit, when } from '@ohos/hypium';
import { DEFAULT_GENERAL_SETTINGS } from '../main/ets/constants/GeneralSettingsConstants';
import { GeneralSettings } from '../main/ets/model/GeneralSettingsModels';
import { LogLevel } from '../main/ets/model/LogModels';
import { RuntimeCommandResponse } from '../main/ets/model/RuntimeModels';
import { GeneralSettingsService } from '../main/ets/services/GeneralSettingsService';
import { runtimeControlService } from '../main/ets/services/RuntimeControlService';

export default function generalSettingsServiceTest() {
  describe('generalSettingsService', () => {
    it('keepsRapidChangesVisibleAndSavesEachIntentInOrder', 0, async () => {
      const mocker = new MockKit();
      const service = new GeneralSettingsService();
      const response: RuntimeCommandResponse<GeneralSettings> = {
        ok: true, code: 'OK', message: '', data: DEFAULT_GENERAL_SETTINGS
      };
      when(mocker.mockFunc(runtimeControlService, runtimeControlService.execute))('generalSettings')
        .afterReturn(Promise.resolve(response));
      const submitted: GeneralSettings[] = [];
      let release: (settings: GeneralSettings) => void = (): void => {};
      when(mocker.mockFunc(service, service.save))(ArgumentMatchers.anyObj)
        .afterAction((settings: GeneralSettings): Promise<GeneralSettings> => {
          submitted.push(settings);
          return submitted.length === 1 ? new Promise<GeneralSettings>((resolve): void => { release = resolve; }) :
            Promise.resolve(settings);
        });
      let current = DEFAULT_GENERAL_SETTINGS;
      const unsubscribe = service.subscribe((settings: GeneralSettings): void => { current = settings; });
      try {
        await service.load();
        const enable = service.update((next: GeneralSettings): void => { next.logCapture = true; });
        const level = service.update((next: GeneralSettings): void => { next.logLevel = LogLevel.DEBUG; });
        const disable = service.update((next: GeneralSettings): void => { next.logCapture = false; });
        expect(current.logCapture).assertFalse();
        expect(current.logLevel).assertEqual(LogLevel.DEBUG);
        expect(current.allowLan).assertFalse();
        await Promise.resolve();
        expect(submitted.length).assertEqual(1);
        expect(submitted[0].logCapture).assertTrue();
        release(submitted[0]);
        await Promise.all([enable, level, disable]);
        expect(submitted.length).assertEqual(3);
        expect(submitted[1].logCapture).assertTrue();
        expect(submitted[1].logLevel).assertEqual(LogLevel.DEBUG);
        expect(submitted[2].logCapture).assertFalse();
        expect(current.logCapture).assertFalse();
        expect(service.isSaving()).assertFalse();
      } finally {
        unsubscribe();
        mocker.clear(service);
        mocker.clear(runtimeControlService);
      }
    });

    it('rollsBackOnlyTheFailedChangeAndContinuesTheQueue', 0, async () => {
      const mocker = new MockKit();
      const service = new GeneralSettingsService();
      const response: RuntimeCommandResponse<GeneralSettings> = {
        ok: true, code: 'OK', message: '', data: DEFAULT_GENERAL_SETTINGS
      };
      when(mocker.mockFunc(runtimeControlService, runtimeControlService.execute))('generalSettings')
        .afterReturn(Promise.resolve(response));
      const submitted: GeneralSettings[] = [];
      let fail: (error: Error) => void = (): void => {};
      when(mocker.mockFunc(service, service.save))(ArgumentMatchers.anyObj)
        .afterAction((settings: GeneralSettings): Promise<GeneralSettings> => {
          submitted.push(settings);
          return submitted.length === 1 ? new Promise<GeneralSettings>((_resolve, reject): void => { fail = reject; }) :
            Promise.resolve(settings);
        });
      let current = DEFAULT_GENERAL_SETTINGS;
      const unsubscribe = service.subscribe((settings: GeneralSettings): void => { current = settings; });
      try {
        await service.load();
        let failed = false;
        const enable = service.update((next: GeneralSettings): void => { next.logCapture = true; })
          .catch((): void => { failed = true; });
        const level = service.update((next: GeneralSettings): void => { next.logLevel = LogLevel.WARNING; });
        expect(current.logCapture).assertTrue();
        expect(current.logLevel).assertEqual(LogLevel.WARNING);
        await Promise.resolve();
        fail(new Error('save failed'));
        await Promise.all([enable, level]);
        expect(failed).assertTrue();
        expect(submitted[1].logCapture).assertFalse();
        expect(current.logCapture).assertFalse();
        expect(current.logLevel).assertEqual(LogLevel.WARNING);
        expect(current.mixedPort).assertEqual(DEFAULT_GENERAL_SETTINGS.mixedPort);
        expect(service.isSaving()).assertFalse();
      } finally {
        unsubscribe();
        mocker.clear(service);
        mocker.clear(runtimeControlService);
      }
    });
  });
}
