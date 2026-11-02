import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';

void main() {
  test('missing LAN addresses use a translated device-neutral placeholder', () {
    expect(
      DeviceHostingNotifier.endpointFor(null, 8080, 'en'),
      'http://<device-ip>:8080/v1/',
    );
    expect(
      DeviceHostingNotifier.endpointFor(null, 8080, 'fr'),
      contains('<adresse-ip-appareil>'),
    );
    expect(
      DeviceHostingNotifier.endpointFor(null, 8080, 'es'),
      contains('<ip-del-dispositivo>'),
    );
    expect(
      DeviceHostingNotifier.endpointFor('192.168.1.2', 8080, 'fr'),
      'http://192.168.1.2:8080/v1/',
    );
  });
}
