import { describe, expect, it } from '@ohos/hypium';
import { LogLevel, LogRecord, LogSnapshot } from '../main/ets/model/LogModels';
import { buildLogFileName, filterLogs, formatLogExport, formatLogTime, isValidLogSnapshot } from '../main/ets/utils/LogUtils';
import { AppPage } from '../main/ets/model/NavigationModels';
import { AppNavigationState } from '../main/ets/navigation/AppNavigationState';

export default function logsTest() {
  describe('logs', () => {
    const timestamp = new Date(2026, 9, 23, 8, 9, 5, 12).getTime();
    const records: LogRecord[] = [
      { id: '2', time: timestamp + 1000, level: LogLevel.ERROR, message: 'DNS 查询失败 example.com' },
      { id: '1', time: timestamp, level: LogLevel.INFO, message: 'Core is running' }
    ];

    it('opensLogsAsASettingsDetailAndReturnsToSettings', 0, () => {
      const navigation = new AppNavigationState();
      navigation.selectPage(AppPage.LOGS);
      expect(navigation.selectedPage).assertEqual(AppPage.SETTINGS);
      expect(navigation.detailPage).assertEqual(AppPage.LOGS);
      expect(navigation.activityOpen).assertTrue();
      navigation.selectPage(AppPage.SETTINGS);
      expect(navigation.activityOpen).assertFalse();
      navigation.selectPage(AppPage.LOGS);
      expect(navigation.visitedDetails.length).assertEqual(1);
    });

    it('searchesContentLevelAndLocalTimeWithoutChangingRecords', 0, () => {
      expect(filterLogs(records, '  EXAMPLE.COM ').length).assertEqual(1);
      expect(filterLogs(records, '错误')[0].id).assertEqual('2');
      expect(filterLogs(records, 'INFO')[0].id).assertEqual('1');
      expect(filterLogs(records, '08:09:05')[0].id).assertEqual('1');
      expect(filterLogs(records, '  ').length).assertEqual(2);
      expect(filterLogs(records, 'not present').length).assertEqual(0);
      expect(records[0].id).assertEqual('2');
    });

    it('namesExportsUsingTheAppNameAndLocalDateWithoutInvalidFilenameCharacters', 0, () => {
      expect(buildLogFileName('Nlash', timestamp)).assertEqual('Nlash_2026-10-23_08-09-05.log');
      expect(buildLogFileName('应用/名称', timestamp)).assertEqual('应用_名称_2026-10-23_08-09-05.log');
      expect(formatLogTime(timestamp)).assertEqual('2026-10-23 08:09:05.012');
    });

    it('exportsTheSelectedSnapshotInChronologicalOrder', 0, () => {
      expect(formatLogExport(records)).assertEqual('2026-10-23 08:09:05.012 [INFO] Core is running\n' +
        '2026-10-23 08:09:06.012 [ERROR] DNS 查询失败 example.com\n');
      const filtered = formatLogExport(filterLogs(records, 'error'));
      expect(filtered.includes('Core is running')).assertFalse();
      expect(filtered.includes('DNS 查询失败')).assertTrue();
      expect(records[0].id).assertEqual('2');
    });

    it('rejectsMalformedSnapshotsAtTheControlBoundary', 0, () => {
      expect(isValidLogSnapshot({ capture: false, level: LogLevel.INFO, records: [] })).assertTrue();
      expect(isValidLogSnapshot({ capture: true, level: LogLevel.DEBUG, records: records })).assertTrue();
      ['null', '{}', '{"capture":true,"level":"trace","records":[]}',
        '{"capture":"true","level":"info","records":[]}',
        '{"capture":true,"level":"info","records":[null]}',
        '{"capture":true,"level":"info","records":[{"id":"1","time":0,"level":"info","message":"x"}]}']
        .forEach((value: string): void => {
          expect(isValidLogSnapshot(JSON.parse(value) as LogSnapshot)).assertFalse();
        });
    });
  });
}
