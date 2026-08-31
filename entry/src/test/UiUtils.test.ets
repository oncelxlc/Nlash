import { describe, expect, it } from '@ohos/hypium';
import { ResponsiveSizeClass } from '../main/ets/model/ResponsiveModels';
import { formatLocalTime } from '../main/ets/utils/DateUtils';
import { resolveContentWidth, resolveResponsiveMetrics } from '../main/ets/utils/ResponsiveUtils';

export default function uiUtilsTest() {
  describe('uiUtils', () => {
    it('preservesWidthConversionAndInvalidValueFallback', 0, () => {
      const resource: Resource = { bundleName: '', moduleName: '', id: 0, type: 10002, params: [] };
      expect(resolveContentWidth(360)).assertEqual(360);
      expect(resolveContentWidth('640')).assertEqual(640);
      expect(resolveContentWidth(' 900 ')).assertEqual(900);
      expect(resolveContentWidth('640vp')).assertEqual(0);
      expect(resolveContentWidth('invalid')).assertEqual(0);
      expect(resolveContentWidth('')).assertEqual(0);
      expect(resolveContentWidth(Number.NaN)).assertEqual(0);
      expect(resolveContentWidth(Number.POSITIVE_INFINITY)).assertEqual(0);
      expect(resolveContentWidth(resource)).assertEqual(0);
    });

    it('preservesResponsiveBreakpointsAndExpandedOverride', 0, () => {
      expect(resolveResponsiveMetrics(639).sizeClass).assertEqual(ResponsiveSizeClass.COMPACT);
      expect(resolveResponsiveMetrics(640).sizeClass).assertEqual(ResponsiveSizeClass.MEDIUM);
      expect(resolveResponsiveMetrics(899).sizeClass).assertEqual(ResponsiveSizeClass.MEDIUM);
      expect(resolveResponsiveMetrics(900).sizeClass).assertEqual(ResponsiveSizeClass.EXPANDED);
      expect(resolveResponsiveMetrics(0, true).sizeClass).assertEqual(ResponsiveSizeClass.EXPANDED);
    });

    it('formatsLocalTimeAndMissingTimestamps', 0, () => {
      const timestamp = new Date(2026, 7, 31, 12, 34, 56).getTime();
      expect(formatLocalTime(timestamp)).assertEqual(new Date(timestamp).toLocaleTimeString());
      expect(formatLocalTime(0)).assertEqual('--');
      expect(formatLocalTime(-1)).assertEqual('--');
      expect(formatLocalTime(Number.NaN)).assertEqual('--');
    });
  });
}
