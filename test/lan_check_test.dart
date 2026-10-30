import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/lan_check.dart';

void main() {
  test('a public Wi-Fi and a public-only allow rule on a public network', () {
    final check = LanCheck.parse({
      'current': 4,
      'profiles': {'alias': 'Wi-Fi', 'category': 'Public'},
      'rules': [
        {'action': 1, 'profiles': 4},
      ],
    });
    expect(check.publicNetworks, ['Wi-Fi']);
    expect(check.firewall, isTrue);
    expect(check.clear, isFalse);
  });

  test('a block rule for the current profile wins over an allow rule', () {
    final check = LanCheck.parse({
      'current': 2,
      'profiles': [
        {'alias': 'Ethernet', 'category': 'Private'},
      ],
      'rules': [
        {'action': 1, 'profiles': 2},
        {'action': 0, 'profiles': 6},
      ],
    });
    expect(check.publicNetworks, isEmpty);
    expect(check.firewall, isFalse);
  });

  test('rules for other profiles do not count', () {
    final check = LanCheck.parse({
      'current': 2,
      'profiles': [],
      'rules': [
        {'action': 1, 'profiles': 4},
      ],
    });
    expect(check.firewall, isNull);
  });

  test('private network, allowed, no VPN is clear', () {
    final check = LanCheck.parse({
      'current': 2,
      'profiles': [
        {'alias': 'Wi-Fi', 'category': 'Private'},
      ],
      'rules': {'action': 1, 'profiles': 7},
    });
    expect(check.clear, isTrue);
    expect(
      LanCheck.parse(
        {
          'current': 2,
          'rules': {'action': 1, 'profiles': 2},
        },
        vpns: ['NordLynx'],
      ).clear,
      isFalse,
    );
  });

  test('VPN adapter names', () {
    expect(LanCheck.vpnName.hasMatch('NordLynx'), isTrue);
    expect(LanCheck.vpnName.hasMatch('Wi-Fi'), isFalse);
  });
}
