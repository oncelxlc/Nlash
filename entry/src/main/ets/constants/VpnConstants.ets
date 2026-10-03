export const VPN_STATE_EVENT = 'nlash.vpn.state.changed';

export const VPN_STATE_COMMON_EVENT = 'com.zhexian.nlash.event.VPN_STATE_CHANGED';

export const VPN_BUNDLE_NAME = 'com.zhexian.nlash';

export const BOOTSTRAP_PROFILE_SIGNATURE: string = 'bootstrap';

export const BOOTSTRAP_CORE_CONFIG: string = 'port: 0\nsocks-port: 0\nmixed-port: 0\n' +
  'redir-port: 0\ntproxy-port: 0\nallow-lan: false\nexternal-controller: ""\n' +
  'mode: rule\nlog-level: warning\nipv6: false\ngeo-auto-update: false\n' +
  'dns:\n  enable: false\ntun:\n  enable: false\n' +
  'proxy-providers: {}\nrule-providers: {}\nproxies: []\nproxy-groups: []\nrules:\n  - MATCH,REJECT\n';
