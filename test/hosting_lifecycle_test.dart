import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/hosting/presentation/device_hosting_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'chat_test.dart' show TestEngine, TestModels, TestSettings;

class LoadedEngine extends TestEngine {
  @override
  bool get isLoaded => true;
  @override
  bool get isBusy => false;
}

class DelayedHost extends DeviceHostingNotifier {
  static late Completer<String> token;
  @override
  Future<String> readAccessToken() => token.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'stop during keystore startup prevents a later server from appearing',
    () async {
      SharedPreferences.setMockInitialValues({});
      final token = Completer<String>();
      DelayedHost.token = token;
      final container = ProviderContainer(
        overrides: [
          llamaEngineProvider.overrideWithValue(LoadedEngine()),
          modelManagerProvider.overrideWith(TestModels.new),
          settingsProvider.overrideWith(TestSettings.new),
          deviceHostingProvider.overrideWith(DelayedHost.new),
        ],
      );
      final controller = container.read(deviceHostingProvider.notifier);
      addTearDown(() async {
        await controller.stop();
        container.dispose();
      });
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      final starting = controller.start(port: port);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(deviceHostingProvider).starting, true);
      await controller.stop();
      token.complete('a' * 40);
      await starting;
      expect(container.read(deviceHostingProvider).running, false);
      expect(container.read(deviceHostingProvider).starting, false);
    },
  );
}
