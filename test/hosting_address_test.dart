import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';

void main() {
  test('the Wi-Fi address wins over mobile data', () {
    // The S25+ lists rmnet_data0 (192.0.0.2) before wlan0 (10.0.0.222).
    final mobile = DeviceHostingNotifier.rankAddress('rmnet_data0', [
      192,
      0,
      0,
      2,
    ]);
    final wifi = DeviceHostingNotifier.rankAddress('wlan0', [10, 0, 0, 222]);
    final home = DeviceHostingNotifier.rankAddress('wlan0', [192, 168, 1, 20]);
    final cgnat = DeviceHostingNotifier.rankAddress('rmnet1', [100, 72, 3, 4]);
    expect(wifi, greaterThan(mobile));
    expect(home, greaterThan(mobile));
    expect(wifi, greaterThan(cgnat));
  });

  test('on Windows the Wi-Fi beats a VPN adapter in a private range', () {
    final wifi = DeviceHostingNotifier.rankAddress('wi-fi', [10, 0, 0, 187]);
    final vpn = DeviceHostingNotifier.rankAddress('nordlynx', [10, 5, 0, 2]);
    final hyperv = DeviceHostingNotifier.rankAddress(
      'vethernet (default switch)',
      [172, 20, 0, 1],
    );
    final direct = DeviceHostingNotifier.rankAddress(
      'local area connection* 10',
      [192, 168, 137, 1],
    );
    expect(wifi, greaterThan(vpn));
    expect(wifi, greaterThan(hyperv));
    expect(wifi, greaterThan(direct));
  });
}
