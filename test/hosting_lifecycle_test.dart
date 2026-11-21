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
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/hosting/device_model_server.dart';
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
  Future<void> loadServed(
    ModelInfo info,
    LlamaEngine engine, {
    bool vision = false,
  }) async {}
}

class _ReadyHost extends DeviceHostingNotifier {
  @override
  Future<String> readAccessToken() async => 'a' * 40;
}

/// Holds stop() open so a start can try to slip into an identity reset.
class _SlowStopHost extends DeviceHostingNotifier {
  final stopping = Completer<void>();
  int stops = 0;
  @override
  Future<void> stop({String? reason}) {
    stops++;
    return stopping.future;
  }
}

/// Holds the token read open, so a startup is still running when the reset
/// starts: the reset must wait for that bind to wind down.
class _SlowTokenHost extends DeviceHostingNotifier {
  final token = Completer<String>();
  @override
  Future<String> readAccessToken() => token.future;
}

/// No app support directory: the identity files cannot be reached or removed,
/// the way a rejecting secure storage makes the reset fail.
class _UnavailablePaths extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async => null;
}

class _DelayedLanHost extends _ReadyHost {
  final resolving = Completer<void>();
  final firstAddress = Completer<String>();
  final published = <int>[];

  @override
  Future<String?> resolveLanAddress() async {
    if (resolving.isCompleted) return '192.168.1.2';
    resolving.complete();
    return firstAddress.future;
  }

  @override
  Future<void> publishAdvertisement(
    int port,
    String host,
    Object owner,
    bool Function() isCurrent,
  ) async {
    expect(isCurrent(), isTrue);
    published.add(port);
  }
}

class _HeldCloseHost extends _ReadyHost {
  final events = <String>[];
  final closeStarted = Completer<void>();
  final hold = Completer<void>();
  final closed = Completer<void>();

  @override
  Future<String?> resolveLanAddress() async => '192.168.1.2';

  @override
  Future<void> publishAdvertisement(
    int port,
    String host,
    Object owner,
    bool Function() isCurrent,
  ) async {
    expect(isCurrent(), isTrue);
    events.add('publish');
  }

  @override
  Future<void> withdrawAdvertisement(Object? owner) async {
    if (owner != null) events.add('withdraw');
  }

  /// Models a workspace job that ignores cancellation and keeps
  /// `workspace.dispose()` pending.
  @override
  Future<void> closeRuntimes(DeviceModelServer? server, ModelPool? pool) async {
    events.add('close');
    if (!closeStarted.isCompleted) closeStarted.complete();
    await hold.future;
    await super.closeRuntimes(server, pool);
    if (!closed.isCompleted) closed.complete();
  }

  Future<void> release() async {
    if (!hold.isCompleted) hold.complete();
    await closed.future.timeout(const Duration(seconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
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
  test('a superseded LAN lookup cannot publish after restart', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('hosting-lan-race');
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    final host = _DelayedLanHost();
    final container = ProviderContainer(
      overrides: [
        llamaEngineProvider.overrideWithValue(LoadedEngine()),
        modelManagerProvider.overrideWith(TestModels.new),
        settingsProvider.overrideWith(TestSettings.new),
        deviceHostingProvider.overrideWith(() => host),
      ],
    );
    container.read(deviceHostingProvider.notifier);
    addTearDown(() async {
      if (!host.firstAddress.isCompleted) {
        host.firstAddress.complete('192.168.1.1');
      }
      await host.stop();
      container.dispose();
      PathProviderPlatform.instance = previousPaths;
      final marker = File('${dir.path}/hosting-tls.fingerprint');
      if (await marker.exists()) await marker.delete();
      final models = Directory('${dir.path}/models');
      if (await models.exists()) await models.delete();
      await dir.delete();
    });
    final first = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final firstPort = first.port;
    await first.close();
    final superseded = host.start(port: firstPort);
    await Future.any([
      host.resolving.future,
      superseded.then((_) {
        if (!host.resolving.isCompleted) {
          fail(
            container.read(deviceHostingProvider).error ??
                'LAN lookup never started',
          );
        }
      }),
    ]).timeout(const Duration(seconds: 10));
    await host.stop();
    final next = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final nextPort = next.port;
    await next.close();
    await host.start(port: nextPort);
    final restarted = container.read(deviceHostingProvider);
    expect(restarted.running, isTrue);
    expect(host.published, hasLength(1));
    host.firstAddress.complete('192.168.1.1');
    await superseded;
    expect(container.read(deviceHostingProvider), same(restarted));
    expect(host.published, hasLength(1));
  });
  test('stop withdraws the LAN record before a job-bound close', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('hosting-stop-order');
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    final previousTimeout = DeviceHostingNotifier.closeTimeout;
    DeviceHostingNotifier.closeTimeout = const Duration(milliseconds: 200);
    final host = _HeldCloseHost();
    final container = ProviderContainer(
      overrides: [
        llamaEngineProvider.overrideWithValue(LoadedEngine()),
        modelManagerProvider.overrideWith(TestModels.new),
        settingsProvider.overrideWith(TestSettings.new),
        deviceHostingProvider.overrideWith(() => host),
      ],
    );
    addTearDown(() async {
      await host.release();
      container.dispose();
      DeviceHostingNotifier.closeTimeout = previousTimeout;
      PathProviderPlatform.instance = previousPaths;
      final marker = File('${dir.path}/hosting-tls.fingerprint');
      if (await marker.exists()) await marker.delete();
      final models = Directory('${dir.path}/models');
      if (await models.exists()) await models.delete();
      await dir.delete();
    });
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    container.read(deviceHostingProvider.notifier);
    await host.start(port: port);
    expect(container.read(deviceHostingProvider).running, isTrue);
    final clock = Stopwatch()..start();
    await host.stop().timeout(const Duration(seconds: 5));
    expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
    expect(host.closeStarted.isCompleted, isTrue);
    expect(host.events, ['publish', 'withdraw', 'close']);
  });
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

  test('a start during an identity reset is refused', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('hosting-reset-race');
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    final container = ProviderContainer(
      overrides: [
        llamaEngineProvider.overrideWithValue(LoadedEngine()),
        modelManagerProvider.overrideWith(TestModels.new),
        settingsProvider.overrideWith(TestSettings.new),
        deviceHostingProvider.overrideWith(_SlowStopHost.new),
      ],
    );
    final notifier = container.read(deviceHostingProvider.notifier);
    final host = notifier as _SlowStopHost;
    addTearDown(() async {
      if (!host.stopping.isCompleted) host.stopping.complete();
      container.dispose();
      PathProviderPlatform.instance = previousPaths;
      await dir.delete(recursive: true);
    });
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    // The reset is held inside stop(): the old identity is still in place.
    final resetting = host.resetHostIdentity();
    await Future<void>.delayed(Duration.zero);
    unawaited(host.start(port: port, lan: false));
    await Future<void>.delayed(Duration.zero);
    expect(container.read(deviceHostingProvider).starting, isFalse);
    expect(container.read(deviceHostingProvider).running, isFalse);
    host.stopping.complete();
    await resetting;
  });

  test('an identity reset waits for the startup it cancelled', () async {
    SharedPreferences.setMockInitialValues({});
    final previousPaths = PathProviderPlatform.instance;
    // The reset itself fails on the missing support directory: that path runs
    // in microtasks, so only the wait for the startup can keep it open.
    PathProviderPlatform.instance = _UnavailablePaths();
    final container = ProviderContainer(
      overrides: [
        llamaEngineProvider.overrideWithValue(LoadedEngine()),
        modelManagerProvider.overrideWith(TestModels.new),
        settingsProvider.overrideWith(TestSettings.new),
        deviceHostingProvider.overrideWith(_SlowTokenHost.new),
      ],
    );
    final host =
        container.read(deviceHostingProvider.notifier) as _SlowTokenHost;
    addTearDown(() async {
      if (!host.token.isCompleted) host.token.complete('a' * 40);
      container.dispose();
      PathProviderPlatform.instance = previousPaths;
    });
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    // The startup is held before its bind: the reset must not finish first,
    // or the next start would find the port still in use.
    final starting = host.start(port: port, lan: false);
    await Future<void>.delayed(Duration.zero);
    var resetDone = false;
    final resetting = host.resetHostIdentity().then((_) => resetDone = true);
    await Future<void>.delayed(Duration.zero);
    expect(resetDone, isFalse);
    expect(container.read(deviceHostingProvider).resettingIdentity, isTrue);
    host.token.complete('a' * 40);
    await starting;
    await resetting;
    expect(resetDone, isTrue);
    // It did run to its end (and failed on the identity files, as arranged).
    final state = container.read(deviceHostingProvider);
    expect(state.tlsIdentityFailure, isTrue);
    expect(state.resettingIdentity, isFalse);
  });

  test('a token change during an identity reset is refused', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('hosting-reset-token');
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(dir.path);
    final container = ProviderContainer(
      overrides: [
        llamaEngineProvider.overrideWithValue(LoadedEngine()),
        modelManagerProvider.overrideWith(TestModels.new),
        settingsProvider.overrideWith(TestSettings.new),
        deviceHostingProvider.overrideWith(_SlowStopHost.new),
      ],
    );
    final host =
        container.read(deviceHostingProvider.notifier) as _SlowStopHost;
    addTearDown(() async {
      if (!host.stopping.isCompleted) host.stopping.complete();
      container.dispose();
      PathProviderPlatform.instance = previousPaths;
      await dir.delete(recursive: true);
    });
    final resetting = host.resetHostIdentity();
    await Future<void>.delayed(Duration.zero);
    final token = host.regenerateToken();
    await Future<void>.delayed(Duration.zero);
    // The token change must not run its own stop and clear the reset's state.
    expect(host.stops, 1);
    host.stopping.complete();
    await resetting;
    await token;
  });

  test('a rejected identity reset keeps the way out', () async {
    SharedPreferences.setMockInitialValues({});
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _UnavailablePaths();
    final container = ProviderContainer(
      overrides: [settingsProvider.overrideWith(TestSettings.new)],
    );
    addTearDown(() {
      container.dispose();
      PathProviderPlatform.instance = previousPaths;
    });
    await container.read(deviceHostingProvider.notifier).resetHostIdentity();
    final state = container.read(deviceHostingProvider);
    // stop() already cleared the recovery state: the failure keeps both the
    // message and "Reset identity" so the reset can be retried.
    expect(state.tlsIdentityFailure, isTrue);
    expect(state.error, isNotNull);
  });
}
