import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/features/hosting/model_pool.dart';
import 'package:ondevice_llm/features/hosting/presentation/pool_options_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
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

class _RealHttp extends HttpOverrides {}

class _Paths extends PathProviderPlatform {
  final String path;
  _Paths(this.path);
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _Runtime extends LoadedEngine {
  final received = <InferenceSettings>[];
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    received.add(settings);
    yield 'hello';
  }

  bool disposed = false;
  @override
  Future<void> unload() async {}
  @override
  void dispose() => disposed = true;
}

const _extra = ModelInfo(
  id: 'extra',
  displayName: 'Extra',
  fileName: 'extra.gguf',
  sizeBytes: 1,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: 'extra.gguf',
);

class _ProfileModels extends TestModels {
  @override
  ModelManagerState build() {
    final initial = super.build();
    return initial.copyWith(catalog: [...initial.catalog, _extra]);
  }

  @override
  InferenceSettings servedSettings(ModelInfo info) =>
      const InferenceSettings(temperature: 0.17);
  @override
  Future<void> loadServed(ModelInfo info, LlamaEngine engine) async {}
}

class _ReadyHost extends DeviceHostingNotifier {
  @override
  Future<String> readAccessToken() async => 'a' * 40;
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
  for (final desktop in [false, true]) {
    test(
      'hosting uses model settings and dispose releases runtimes: desktop=$desktop',
      () async {
        SharedPreferences.setMockInitialValues({});
        final dir = await Directory.systemTemp.createTemp('hosting-round-c');
        final previousPaths = PathProviderPlatform.instance;
        PathProviderPlatform.instance = _Paths(dir.path);
        DesktopHost.active = desktop;
        final primary = _Runtime();
        final extra = _Runtime();
        final container = ProviderContainer(
          overrides: [
            llamaEngineProvider.overrideWithValue(primary),
            engineFactoryProvider.overrideWithValue(() => extra),
            modelManagerProvider.overrideWith(_ProfileModels.new),
            settingsProvider.overrideWith(TestSettings.new),
            deviceHostingProvider.overrideWith(_ReadyHost.new),
          ],
        );
        final client = _RealHttp().createHttpClient(null);
        var disposed = false;
        addTearDown(() async {
          client.close(force: true);
          if (!disposed) container.dispose();
          DesktopHost.active = false;
          PathProviderPlatform.instance = previousPaths;
          await dir.delete(recursive: true);
        });
        final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = socket.port;
        await socket.close();
        await container
            .read(poolOptionsProvider.notifier)
            .set(const PoolOptions(jit: true));
        final host = container.read(deviceHostingProvider.notifier);
        await host.start(port: port, lan: false);
        expect(container.read(deviceHostingProvider).running, true);
        Future<void> request(String model) async {
          final req = await client.postUrl(
            Uri.parse('http://127.0.0.1:$port/v1/chat/completions'),
          );
          req.headers.set('Authorization', 'Bearer ${'a' * 40}');
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'model': model,
              'messages': [
                {'role': 'user', 'content': 'hi'},
              ],
            }),
          );
          final response = await req.close();
          expect(response.statusCode, 200);
          await response.drain<void>();
        }

        await request('test');
        expect(primary.received.single.temperature, 0.17);
        if (desktop) await request('extra');
        container.dispose();
        disposed = true;
        for (var i = 0; desktop && !extra.disposed && i < 100; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        if (desktop) expect(extra.disposed, true);
      },
    );
  }
}
