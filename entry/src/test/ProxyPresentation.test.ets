import { describe, expect, it } from '@ohos/hypium';
import { filterProxyNodes, proxyDelayLabel } from '../main/ets/utils/RuntimeUtils';
import { proxyGroupColumnCount, proxyNodeColumnCount } from '../main/ets/utils/ResponsiveUtils';
import { ProxyGroupSnapshot } from '../main/ets/model/RuntimeModels';

export default function proxyPresentationTest() {
  describe('proxyPresentation', () => {
    const group: ProxyGroupSnapshot = {
      name: 'YKKCLOUD', type: 'Selector', selected: 'Singapore 05 | MITM', selectable: true, hidden: false,
      nodes: [
        { name: 'Singapore 05 | MITM', type: 'Vless', alive: true, tested: true, delay: 158, udp: true },
        { name: '[BETA-3] HongKong [0.1x]', type: 'Vless', alive: false, tested: true, delay: -1, udp: true },
        { name: 'AutoSelection', type: 'URLTest', alive: false, tested: false, delay: 0, udp: false }
      ]
    };

    it('filtersWithoutLosingSelectionOrMutatingSnapshots', 0, () => {
      expect(filterProxyNodes(group, '  ').length).assertEqual(3);
      expect(filterProxyNodes(group, 'ykkcloud').length).assertEqual(3);
      expect(filterProxyNodes(group, '  SINGAPORE ')[0]).assertEqual(group.nodes[0]);
      expect(filterProxyNodes(group, 'vless').length).assertEqual(2);
      expect(filterProxyNodes(group, 'missing').length).assertEqual(0);
      expect(group.nodes.length).assertEqual(3);
      expect(group.selected).assertEqual('Singapore 05 | MITM');
    });

    it('fitsFoldedPhonesAndUnfoldedScreensWithLargeText', 0, () => {
      expect(proxyGroupColumnCount(346)).assertEqual(1);
      expect(proxyGroupColumnCount(366)).assertEqual(1);
      expect(proxyGroupColumnCount(639)).assertEqual(1);
      expect(proxyGroupColumnCount(640)).assertEqual(2);
      expect(proxyGroupColumnCount(717)).assertEqual(2);
      expect(proxyGroupColumnCount(781)).assertEqual(2);
      expect(proxyGroupColumnCount(717, 1.3)).assertEqual(1);
      expect(proxyNodeColumnCount(314)).assertEqual(2);
      expect(proxyNodeColumnCount(279)).assertEqual(1);
      expect(proxyNodeColumnCount(334, 1.3)).assertEqual(1);
      expect(proxyNodeColumnCount(669, 1.3)).assertEqual(2);
    });

    it('providesReadableDelayStates', 0, () => {
      expect(proxyDelayLabel(group.nodes[0], false)).assertEqual('158 ms');
      expect(proxyDelayLabel(group.nodes[1], false)).assertEqual('超时');
      expect(proxyDelayLabel(group.nodes[2], false)).assertEqual('未测速');
      expect(proxyDelayLabel(group.nodes[0], true)).assertEqual('测速中');
    });
  });
}
