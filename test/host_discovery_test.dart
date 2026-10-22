import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/host_discovery.dart';

void main() {
  test('local discovery exposes an endpoint, no pairing credentials', () {
    final host = DiscoveredHost.parse({
      'name': 'My host',
      'host': '192.168.1.2',
      'port': 8787,
      'key': 'must not transfer',
    });
    expect(host!.endpoint, 'http://192.168.1.2:8787/v1/');
    expect(host.name, 'My host');
    expect(
      DiscoveredHost.parse({
        'name': 'V6',
        'host': 'fd00::12',
        'port': 8787,
      })!.endpoint,
      'http://[fd00::12]:8787/v1/',
    );
  });
  test('discovery cannot create arbitrary internet or malformed endpoints', () {
    for (final host in [
      '8.8.8.8',
      'example.com',
      '127.0.0.1',
      '224.0.0.1',
      '169.254.1.2',
      '::1',
      'fe80::1',
    ]) {
      expect(
        DiscoveredHost.parse({'name': 'host', 'host': host, 'port': 8787}),
        isNull,
      );
    }
    for (final port in [0, 65536, 1.5, double.nan]) {
      expect(
        DiscoveredHost.parse({
          'name': 'host',
          'host': '10.1.2.3',
          'port': port,
        }),
        isNull,
      );
    }
  });
}
