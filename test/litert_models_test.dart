import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/adapters/adapter_store.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/litert_engine.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_test.dart' show TestEngine, TestSettings, testModel;
import 'local_backup_service_test.dart' show BackupPaths;

final _liteRt = liteRtCatalog.first.copyWith(
  isDownloaded: true,
  localPath: 'test.litertlm',
);

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [testModel, _liteRt]);
  }
}

/// The chat model is the LiteRT file, already loaded.
class _LiteRtModels extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return ModelManagerState(catalog: [_liteRt], loadedModelId: _liteRt.id);
  }

  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
    void Function()? onLoadStart,
    bool vision = false,
  }) async {}
}

/// A grammar override left by a chat that used a .gguf model.
class _GrammarSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(
    responseFormat: ResponseFormat.gbnf,
    grammar: 'root ::= "x"',
  );
}

/// Records what the chat asks the LiteRT engine to generate.
class _FakeLiteRt extends LiteRtEngine {
  InferenceSettings? generated;

  @override
  Map<String, dynamic> get metrics => const {'contextSize': 4096};

  @override
  bool get isLoaded => true;

  @override
  bool holdsLoad(String path, LiteRtBackend backend, {required bool vision}) =>
      true;

  @override
  Future<void> loadModel(
    String path, {
    required LiteRtBackend backend,
    required bool vision,
  }) async {}

  @override
  Future<void> unload() async {}

  @override
  void dispose() {}

  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => {
    'prompt': '',
    'promptTokens': 1,
    'contextSize': 4096,
    'reservedTokens': 128,
    'availableTokens': 4000,
    'fits': true,
  };

  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    generated = settings;
    yield 'answer';
  }
}

class _Adapters extends AdaptersNotifier {
  @override
  AdaptersState build() {
    ready = Future.value();
    return const AdaptersState();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'model manager loads LiteRT, reuses it, then switches to GGUF',
    () async {
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const methods = MethodChannel('ondevice_llm/litert');
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methods, (call) async {
        calls.add(call);
        return call.method == 'load' ? {'backend': 'cpu'} : null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(methods, null));

      final liteRt = LiteRtEngine();
      final llama = TestEngine();
      final container = ProviderContainer(
        overrides: [
          liteRtAvailableProvider.overrideWithValue(true),
          liteRtEngineProvider.overrideWithValue(liteRt),
          llamaEngineProvider.overrideWithValue(llama),
          modelManagerProvider.overrideWith(_Models.new),
          adaptersProvider.overrideWith(_Adapters.new),
          settingsProvider.overrideWith(TestSettings.new),
        ],
      );
      addTearDown(container.dispose);
      final manager = container.read(modelManagerProvider.notifier);
      const settings = InferenceSettings(
        backend: GpuBackend.cpu,
        liteRtBackend: LiteRtBackend.gpu,
        speculationMode: 'off',
      );
      await manager.loadModel(_liteRt, settings: settings);
      await manager.loadModel(_liteRt, settings: settings);
      expect(calls.map((c) => c.method), ['load']);
      expect((calls.single.arguments as Map)['path'], _liteRt.localPath);
      expect((calls.single.arguments as Map)['backend'], 'gpu');
      expect((calls.single.arguments as Map)['vision'], isTrue);
      expect(llama.loadedWith, isNull);
      expect(container.read(activeLocalEngineProvider), same(liteRt));

      await manager.loadModel(testModel, settings: settings);
      expect(calls.map((c) => c.method), ['load', 'unload']);
      expect(liteRt.isLoaded, isFalse);
      expect(llama.loadedWith?.backend, GpuBackend.cpu);
      expect(container.read(activeLocalEngineProvider), same(llama));
    },
  );

  test(
    'a LiteRT turn drops a GBNF override instead of validating free text',
    () async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final liteRt = _FakeLiteRt();
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          liteRtAvailableProvider.overrideWithValue(true),
          liteRtEngineProvider.overrideWithValue(liteRt),
          llamaEngineProvider.overrideWithValue(TestEngine()),
          modelManagerProvider.overrideWith(_LiteRtModels.new),
          settingsProvider.overrideWith(_GrammarSettings.new),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });
      expect(await container.read(chatProvider.notifier).send('Hello'), isTrue);
      // LiteRT cannot hold the reply to a grammar: the turn runs as plain
      // text, so the answer is not reported as structured output.
      expect(liteRt.generated?.responseFormat, ResponseFormat.text);
      expect(liteRt.generated?.grammar, isEmpty);
      expect(liteRt.generated?.toolsEnabled, isFalse);
    },
  );

  test('the local server never hands a LiteRT file to llama.cpp', () async {
    SharedPreferences.setMockInitialValues({});
    final liteRt = LiteRtEngine();
    final llama = TestEngine();
    final container = ProviderContainer(
      overrides: [
        liteRtAvailableProvider.overrideWithValue(true),
        liteRtEngineProvider.overrideWithValue(liteRt),
        llamaEngineProvider.overrideWithValue(llama),
        modelManagerProvider.overrideWith(_Models.new),
        adaptersProvider.overrideWith(_Adapters.new),
        settingsProvider.overrideWith(TestSettings.new),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(modelManagerProvider.notifier).loadServed(_liteRt, llama),
      throwsUnsupportedError,
    );
    expect(llama.loadedWith, isNull);
  });

  test('ModelStorage accepts and hashes LiteRT models and partials', () async {
    final dir = await Directory.systemTemp.createTemp('litert-model-test-');
    final paths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = BackupPaths(dir.path, dir.path);
    try {
      final file = await ModelStorage.modelFile('example.LiteRTLM');
      final bytes = [1, 2, 3, 4];
      final hash = sha256.convert(bytes).toString();
      await file.writeAsBytes(bytes);
      final partial = await File('${file.path}.part').writeAsBytes(bytes);
      expect(await ModelStorage.validateAndHash(file.path), hash);
      expect(await ModelStorage.validateAndHash(partial.path), hash);
      await expectLater(
        ModelStorage.modelFile('../example.litertlm'),
        throwsFormatException,
      );
      await ModelStorage.deletePartial('example.LiteRTLM');
      expect(await partial.exists(), isFalse);
    } finally {
      PathProviderPlatform.instance = paths;
      final models = Directory.fromUri(dir.uri.resolve('models/'));
      if (await models.exists()) {
        for (final entry in await models.list().toList()) {
          await entry.delete();
        }
        await models.delete();
      }
      await dir.delete();
    }
  });

  test('the three LiteRT catalog files have pinned HTTPS URLs and SHA-256', () {
    final entries = bundledCatalog.where((m) => m.isLiteRt).toList();
    expect(entries, liteRtCatalog);
    expect(entries, hasLength(3));
    expect(desktopCatalog.where((m) => m.isLiteRt), isEmpty);
    // Every LiteRT model is offered photos: the runtime reads the file's own
    // metadata at load and drops the vision backend for a text-only one.
    expect(entries.where((m) => m.liteRtVision), hasLength(3));
    for (final model in entries) {
      final uri = Uri.parse(model.downloadUrl!);
      expect(uri.scheme, 'https');
      expect(uri.host, 'huggingface.co');
      expect(uri.pathSegments[2], 'resolve');
      expect(uri.pathSegments[3], matches(r'^[0-9a-f]{40}$'));
      expect(uri.pathSegments.last, model.fileName);
      expect(model.sha256, matches(r'^[0-9a-f]{64}$'));
      expect(model.sizeBytes, greaterThan(0));
    }
  });
}
