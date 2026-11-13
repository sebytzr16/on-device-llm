import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/load_settings/analytical_estimate.dart';
import 'package:ondevice_llm/desktop/load_settings_dialog.dart';
import 'package:ondevice_llm/desktop/model_speed_section.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_pages_2_test.dart' show TestModels, TestSettings, testModel;

class _Models extends TestModels {
  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
    void Function()? onLoadStart,
    bool vision = false,
  }) async {}
}

class _DelayedEngine extends LlamaEngine {
  final estimateGate = Completer<Map<String, dynamic>>();
  final generationGate = Completer<void>();
  int generations = 0, cancellations = 0, estimates = 0;
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) {
    estimates++;
    return estimateGate.future;
  }

  @override
  Future<Map<String, dynamic>> probe() async => {};
  @override
  Future<Map<String, dynamic>> adapterInfo(String path) async => {};
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => {'promptTokens': 32, 'fits': true};
  @override
  Map<String, dynamic> get metrics => {
    'contextSize': 4096,
    'promptTokens': 32,
    'tokens': 128,
    'firstTokenMs': 100,
    'tokensPerSecond': 100,
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
    generations++;
    await generationGate.future;
    yield 'same answer';
  }

  @override
  void cancel() {
    cancellations++;
  }
}

void main() {
  test('FP8 KV uses one byte per element, including separate K/V choices', () {
    const metadata = GgufMetadata(
      version: 3,
      tensorCount: 1,
      blockCount: 2,
      headCount: 4,
      kvHeadCount: 2,
      embeddingLength: 512,
    );
    const fp8 = InferenceSettings(
      contextSize: 4096,
      kvCacheType: KvCacheType.f8_e4m3,
    );
    expect(kvCacheBytes(metadata, fp8), 2 * 2 * 4096 * (128 + 128));
    expect(
      kvCacheBytes(metadata, fp8.copyWith(vCacheType: KvCacheType.q8_0)),
      2 * 2 * 4096 * (128 + 4 * 34),
    );
  });
  test(
    'analytical estimate is synchronous and accounts for GQA and separate KV types',
    () {
      const metadata = GgufMetadata(
        version: 3,
        tensorCount: 1,
        blockCount: 32,
        embeddingLength: 4096,
        headCount: 32,
        kvHeadCount: 8,
        weightsBytes: 4 * 1024 * 1024 * 1024,
      );
      final estimate = analyticalMemoryEstimate(
        metadata: metadata,
        weightsBytes: 0,
        settings: const InferenceSettings(
          contextSize: 4096,
          nGpuLayers: 16,
          kvCacheType: KvCacheType.q8_0,
          vCacheType: KvCacheType.q4_0,
        ),
      );
      expect(
        estimate['kvCacheMb'],
        32 * 8 * 4096 * (4 * 34 + 4 * 18) / (1024 * 1024),
      );
      expect(estimate['weightsMb'], 4096);
      expect(estimate['computeBufferMb'], greaterThan(0));
      expect(
        (estimate['ramNeedMb'] as num) + (estimate['vramNeedMb'] as num),
        closeTo(
          4096 +
              (estimate['kvCacheMb'] as num) +
              (estimate['computeBufferMb'] as num),
          0.001,
        ),
      );
    },
  );

  test('sliding-window and shared-KV layers keep a small cache; the draft '
      'goes on the card and the card size shows before measuring', () {
    // Gemma 4 E4B shape: 42 blocks, 18 share earlier caches, every 6th
    // layer full attention, 512-token window with narrower SWA heads.
    final metadata = GgufMetadata(
      version: 3,
      tensorCount: 1,
      blockCount: 42,
      embeddingLength: 2560,
      headCount: 8,
      kvHeadCount: 2,
      keyLength: 512,
      valueLength: 512,
      slidingWindow: 512,
      keyLengthSwa: 256,
      valueLengthSwa: 256,
      sharedKvLayers: 18,
      swaLayers: [for (var i = 0; i < 42; i++) (i + 1) % 6 != 0],
      weightsBytes: 5 * 1024 * 1024 * 1024,
    );
    const settings = InferenceSettings(
      contextSize: 32768,
      nGpuLayers: 999,
      kvCacheType: KvCacheType.q8_0,
      vCacheType: KvCacheType.q8_0,
    );
    final estimate = analyticalMemoryEstimate(
      metadata: metadata,
      weightsBytes: 0,
      settings: settings,
      draftBytes: 300 * 1024 * 1024,
      hardware: const {
        'devices': [
          {'type': 'gpu', 'totalMb': 8192, 'freeMb': 7100},
        ],
      },
    );
    final batch = settings.effectiveMicroBatchSize;
    const full = 2 * 32768 * 2 * 16 * 34;
    final swa = 2 * (512 + batch) * 2 * 8 * 34;
    // 24 own layers: 4 full attention, 20 windowed.
    expect(estimate['kvCacheMb'], (4 * full + 20 * swa) / (1024 * 1024));
    expect(estimate['kvCacheMb'] as num, lessThan(400));
    expect(estimate['draftMb'], 300);
    expect(estimate['ramNeedMb'] as num, lessThan(1));
    expect(estimate['vramTotalMb'], 8192);
    expect(estimate['vramFreeMb'], 7100);
  });

  test('GGUF period pattern marks every n-th layer as full attention', () {
    final layers = GgufMetadata.swaPattern(6, 12, 1024);
    expect(layers, [for (var i = 0; i < 12; i++) i != 5 && i != 11]);
    expect(GgufMetadata.swaPattern(null, 4, 1024), [true, true, true, true]);
    expect(GgufMetadata.swaPattern(null, 4, null), isNull);
  });

  testWidgets(
    'estimate is immediate and late refinement never cancels a speed test',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = _DelayedEngine();
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(_Models.new),
          llamaEngineProvider.overrideWithValue(engine),
          llamaEstimatorProvider.overrideWithValue(engine),
          modelSpeedEngineProvider.overrideWithValue(engine),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDesktopLoadSettings(context, testModel),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final t = AppLocalizationsEn();
      expect(engine.estimateGate.isCompleted, isFalse);
      expect(engine.estimates, greaterThan(0));
      expect(find.text(t.desktopLoadSettingsMeasuring), findsNothing);
      expect(find.textContaining('GB'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('desktop-optimize')))
            .onPressed,
        isNotNull,
      );
      final speed = find.widgetWithText(OutlinedButton, t.desktopBenchStart);
      expect(tester.widget<OutlinedButton>(speed).onPressed, isNotNull);
      await tester.ensureVisible(speed);
      await tester.tap(speed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.generations, greaterThan(0));
      expect(container.read(sessionBusyProvider), isTrue);
      // Move the active speed test outside the scroll viewport as the estimate
      // returns: neither scrolling nor rebuilding may dispose its run.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1500));
      await tester.pump();
      engine.estimateGate.complete({
        'layers': 24,
        'contextTrain': 4096,
        'ramNeedMb': 1200,
        'vramNeedMb': 1800,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(engine.cancellations, 0);
      expect(container.read(sessionBusyProvider), isTrue);
      engine.generationGate.complete();
      await tester.pumpAndSettle();
      expect(container.read(sessionBusyProvider), isFalse);
      expect(engine.generations, greaterThan(1));
      expect(engine.cancellations, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
