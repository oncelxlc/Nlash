import { describe, expect, it } from '@ohos/hypium';
import { DEFAULT_DASHBOARD_CARD_ORDER } from '../main/ets/constants/DashboardConstants';
import { DashboardCard } from '../main/ets/model/DashboardModels';
import {
  dashboardCardSpan, moveDashboardCard, normalizeDashboardCardOrder, resolveDashboardCardOrder
} from '../main/ets/utils/DashboardUtils';

export default function dashboardLayoutTest() {
  describe('dashboardLayout', () => {
    it('adaptsOnlyTheDefaultLayoutToTheAvailableColumns', 0, () => {
      const compact = resolveDashboardCardOrder(undefined, true);
      expect(compact.slice(0, 4).join(',')).assertEqual('publicNetwork,speed,mode,vpn');
      expect(resolveDashboardCardOrder(undefined, false).join(','))
        .assertEqual('publicNetwork,speed,mode,vpn,services,configuration,memory,groups,connections');
      const saved = DEFAULT_DASHBOARD_CARD_ORDER.slice().reverse();
      expect(resolveDashboardCardOrder(saved, true).join(',')).assertEqual(saved.join(','));
      expect(resolveDashboardCardOrder(saved, false).join(',')).assertEqual(saved.join(','));
      expect(resolveDashboardCardOrder(DEFAULT_DASHBOARD_CARD_ORDER, true).join(','))
        .assertEqual(DEFAULT_DASHBOARD_CARD_ORDER.join(','));
    });

    it('restoresDefaultLayoutForMissingOrUnknownCards', 0, () => {
      expect(normalizeDashboardCardOrder([]).join(',')).assertEqual(DEFAULT_DASHBOARD_CARD_ORDER.join(','));
      expect(normalizeDashboardCardOrder(['unknown']).join(','))
        .assertEqual(DEFAULT_DASHBOARD_CARD_ORDER.join(','));
    });

    it('preservesSavedOrderAndAddsMissingCardsWithoutDuplicates', 0, () => {
      const cards = normalizeDashboardCardOrder(['memory', 'mode', 'memory', 'unknown']);
      expect(cards.length).assertEqual(DEFAULT_DASHBOARD_CARD_ORDER.length);
      expect(new Set(cards).size).assertEqual(cards.length);
      expect(cards[0]).assertEqual(DashboardCard.MEMORY);
      expect(cards[1]).assertEqual(DashboardCard.MODE);
      expect(cards[2]).assertEqual(DashboardCard.PUBLIC_NETWORK);
      expect(normalizeDashboardCardOrder(DEFAULT_DASHBOARD_CARD_ORDER.slice().reverse()).join(','))
        .assertEqual(DEFAULT_DASHBOARD_CARD_ORDER.slice().reverse().join(','));
    });

    it('movesCardsInBothDirectionsWithoutChangingTheOriginal', 0, () => {
      const cards = [DashboardCard.MODE, DashboardCard.CONFIGURATION, DashboardCard.SPEED];
      expect(moveDashboardCard(cards, 0, 2).join(',')).assertEqual('configuration,speed,mode');
      expect(moveDashboardCard(cards, 2, 0).join(',')).assertEqual('speed,mode,configuration');
      expect(cards.join(',')).assertEqual('mode,configuration,speed');
    });

    it('ignoresCanceledOrInvalidMoves', 0, () => {
      const cards = DEFAULT_DASHBOARD_CARD_ORDER;
      expect(moveDashboardCard(cards, -1, 0).join(',')).assertEqual(cards.join(','));
      expect(moveDashboardCard(cards, 0, cards.length).join(',')).assertEqual(cards.join(','));
      expect(moveDashboardCard(cards, 0.5, 1).join(',')).assertEqual(cards.join(','));
      expect(moveDashboardCard(cards, 0, Number.NaN).join(',')).assertEqual(cards.join(','));
      expect(moveDashboardCard(cards, 1, 1).join(',')).assertEqual(cards.join(','));
    });

    it('keepsCardDimensionsAfterReordering', 0, () => {
      const cards = moveDashboardCard(DEFAULT_DASHBOARD_CARD_ORDER, 0, 7);
      expect(dashboardCardSpan(cards[7]).join(',')).assertEqual('2,1');
      expect(dashboardCardSpan(DashboardCard.SPEED).join(',')).assertEqual('2,1');
      expect(dashboardCardSpan(DashboardCard.VPN).join(',')).assertEqual('2,1');
      expect(dashboardCardSpan(DashboardCard.CONFIGURATION).join(',')).assertEqual('1,1');
      expect(dashboardCardSpan(DashboardCard.PUBLIC_NETWORK).join(',')).assertEqual('2,1');
      expect(dashboardCardSpan(DashboardCard.DURATION).join(',')).assertEqual('1,1');
      expect(dashboardCardSpan(DashboardCard.CONNECTIONS).join(',')).assertEqual('2,1');
      expect(dashboardCardSpan(DashboardCard.MEMORY).join(',')).assertEqual('1,1');
      DEFAULT_DASHBOARD_CARD_ORDER.forEach((card: DashboardCard): void => {
        expect(dashboardCardSpan(card, true).join(',')).assertEqual('2,1');
      });
    });

    it('mergesLegacyTrafficAndDurationCardsWithoutLosingSavedOrder', 0, () => {
      const restored = normalizeDashboardCardOrder(['traffic', 'memory', 'speed', 'duration', 'publicNetwork', 'mode']);
      expect(restored.slice(0, 4).join(',')).assertEqual('speed,memory,publicNetwork,mode');
      expect(new Set(restored).size).assertEqual(DEFAULT_DASHBOARD_CARD_ORDER.length);
      expect(restored.includes(DashboardCard.TRAFFIC)).assertFalse();
      expect(restored.includes(DashboardCard.DURATION)).assertFalse();
    });
  });
}
