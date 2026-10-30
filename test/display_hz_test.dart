import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/core/platform/frame_timing_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ondevice_llm/desktop');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final originalDesktop = DesktopHost.active;

  tearDown(() {
    DesktopHost.active = originalDesktop;
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('desktop refresh rate uses runner channel', () async {
    DesktopHost.active = true;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'refreshRate');
      return 240;
    });
    expect(await DeviceDisplay.refreshRate(), 240);
  });

  test('desktop refresh rate falls back when runner is absent', () async {
    DesktopHost.active = true;
    expect(await DeviceDisplay.refreshRate(), 0);
  });

  test('frame logger is disabled without the dart define', () async {
    expect(FrameTimingLog.enabled, isFalse);
    await FrameTimingLog().start();
  });
}
