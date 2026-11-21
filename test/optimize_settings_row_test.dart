import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/optimize/model_speed_engine_provider.dart';
import 'package:ondevice_llm/features/optimize/optimize_controller.dart';
import 'package:ondevice_llm/features/optimize/optimize_settings_row.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_pages_2_test.dart' show TestModels, TestSettings, testModel;

const _current = InferenceSettings(
  contextSize: 4096,
  nGpuLayers: 3,
  kvCacheType: KvCacheType.q8_0,
);

class _Estimator extends LlamaEngine {
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => {
    'layers': 24,
    'gpuLayers': settings.nGpuLayers.clamp(0, 24),
    'ramNeedMb': 2048,
    'ramAvailableMb': 16384,
    'vramNeedMb': 1000 + settings.nGpuLayers.clamp(0, 24) * 200,
    'vramFreeMb': 5000,
  };
}

/// A manager that follows its own loads and unloads, so the controller sees a
/// real runtime state.
class _Models extends TestModels {
  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
    void Function()? onLoadStart,
    bool vision = false,
  }) async {
    state = state.copyWith(loadedModelId: info.id);
  }

  @override
  Future<void> unloadModel({bool ownsBusy = false}) async {
    state = state.copyWith(clearLoaded: true);
  }
}

class _Engine extends Fake implements TextEngine {
  Completer<void>? gate;
  @override
  Map<String, dynamic> get metrics => {
    'contextSize': 32768,
    'promptTokens': 32,
    'tokens': 128,
    'firstTokenMs': 100,
    'tokensPerSecond': 200,
  };
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => {'promptTokens': 32, 'fits': true};
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    if (gate != null) await gate!.future;
    yield 'A seed absorbs water and grows roots toward sunlight.';
  }

  @override
  void cancel() {
    if (gate?.isCompleted == false) gate!.complete();
  }
}

ProviderContainer _container({
  bool Function()? generating,
  TextEngine? engine,
}) {
  final c = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith(TestSettings.new),
      modelManagerProvider.overrideWith(_Models.new),
      llamaEstimatorProvider.overrideWithValue(_Estimator()),
      modelSpeedEngineProvider.overrideWithValue(engine ?? _Engine()),
      if (generating != null)
        optimizeGeneratingProvider.overrideWithValue(generating),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Widget _harness(ProviderContainer c) => UncontrolledProviderScope(
  container: c,
  child: MaterialApp(
    theme: DesktopTheme.of(AccentChoice.amber, dark: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const Scaffold(body: OptimizeSettingsRow()),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a stale busy reason no longer speaks for the lock', (
    tester,
  ) async {
    var generating = true;
    final c = _container(generating: () => generating);
    c.read(sessionBusyProvider.notifier).state = true;
    final provider = optimizeControllerProvider(testModel.id);
    await c.read(provider.notifier).start(testModel, _current);
    expect(c.read(provider).busy, OptimizeBusyReason.generating);
    // The reply finished; another model's Optimize run now holds the lock.
    generating = false;
    await tester.pumpWidget(_harness(c));
    await tester.pump();
    final t = AppLocalizationsEn();
    expect(find.text(t.optimizeBusyGenerating), findsNothing);
    expect(find.text(t.optimizeBusyOther), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a running Optimize names itself in the row', (tester) async {
    final engine = _Engine()..gate = Completer<void>();
    final c = _container(engine: engine);
    final provider = optimizeControllerProvider(testModel.id);
    final run = c.read(provider.notifier).start(testModel, _current);
    await tester.pump();
    expect(c.read(provider).running, isTrue);
    await tester.pumpWidget(_harness(c));
    await tester.pump();
    final t = AppLocalizationsEn();
    expect(find.text(t.optimizeBusyRunning), findsOneWidget);
    expect(find.text(t.optimizeBusyOther), findsNothing);
    c.read(provider.notifier).cancel();
    await tester.pumpAndSettle();
    await run;
    expect(tester.takeException(), isNull);
  });
}
