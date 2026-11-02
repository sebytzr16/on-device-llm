import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/model_speed_section.dart';
import 'package:ondevice_llm/desktop/model_tune_section.dart';
import 'package:ondevice_llm/desktop/pc_optimization.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_pages_2_test.dart' show TestModels, TestSettings, testModel;

final _stale = const InferenceSettings().copyWith(
  kvCacheType: KvCacheType.q8_0,
  nGpuLayers: 3,
  flashAttention: false,
  batchSize: 2048,
  cpuThreads: 12,
  temperature: 0.4,
  draftModelId: 'old-draft',
);

Map<String, dynamic> _estimate(InferenceSettings s) => {
  'layers': 24,
  'gpuLayers': s.nGpuLayers,
  'ramNeedMb': 2048,
  'ramAvailableMb': 16384,
  'vramNeedMb': 1000 + s.nGpuLayers * 200,
  'vramFreeMb': 5000,
};

class _Estimator extends LlamaEngine {
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => _estimate(settings);
}

class _Settings extends TestSettings {
  @override
  InferenceSettings build() {
    super.build();
    return _stale;
  }
}

class _Models extends TestModels {
  final loads = <InferenceSettings>[];
  @override
  Future<void> loadModel(
    ModelInfo info, {
    bool forChat = false,
    InferenceSettings? settings,
    void Function()? onLoadStart,
    bool vision = false,
  }) async {
    loads.add(settings!);
  }
}

class _Engine extends Fake implements TextEngine {
  Completer<void>? gate;
  int calls = 0;
  @override
  Map<String, dynamic> get metrics => {
    'contextSize': 32768,
    'promptTokens': 32,
    'tokens': 128,
    'firstTokenMs': 100,
    'tokensPerSecond': 100,
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
    calls++;
    if (gate != null) await gate!.future;
    yield 'same answer';
  }

  @override
  void cancel() {
    if (gate?.isCompleted == false) gate!.complete();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'optimization resets hardware, keeps sampling and chooses maximum fitting F16 layers',
    () async {
      final result = await pcOptimizationDefaults(
        current: _stale,
        defaults: const InferenceSettings(),
        estimate: (s) async => _estimate(s),
      );
      final expected = ((5000 - 1000 - result.vramReserveMb) / 200).floor();
      expect(result.nGpuLayers, expected);
      expect(result.kvCacheType, KvCacheType.fp16);
      expect(result.flashAttention, isTrue);
      expect(result.draftModelId, isEmpty);
      expect(result.mtp, isFalse);
      expect(result.temperature, 0.4);
      expect(result.explicitOverrides, isNot(contains('kvCacheType')));
      expect(result.explicitOverrides, contains('temperature'));
    },
  );

  test(
    'a MoE whose fit moves experts to RAM keeps every layer asked for',
    () async {
      final result = await pcOptimizationDefaults(
        current: _stale,
        defaults: const InferenceSettings(),
        estimate: (s) async => s.nGpuLayers >= 999
            ? {..._estimate(s), 'gpuExpertsOnCpu': true, 'vramNeedMb': 3000}
            : _estimate(s),
      );
      expect(result.nGpuLayers, 999);
      expect(result.kvCacheType, KvCacheType.fp16);
    },
  );

  test(
    'every layer with a q8_0 cache wins over F16 with some layers (E4B)',
    () async {
      // Gemma 4 E4B on an 8 GB card: F16 fits 33 of 43 layers (16 tok/s),
      // q8_0 fits all 43 with the projector moved to RAM (101 tok/s).
      Map<String, dynamic> e4b(InferenceSettings s) {
        final f16 = s.kvCacheType == KvCacheType.fp16;
        final placed = s.nGpuLayers >= 999 ? (f16 ? 33 : 43) : s.nGpuLayers;
        return {
          'layers': 43,
          'gpuLayers': placed,
          'ramNeedMb': 2048,
          'ramAvailableMb': 16384,
          'vramNeedMb': 1000 + placed * (f16 ? 180 : 115),
          'vramFreeMb': 7100,
        };
      }

      final result = await pcOptimizationDefaults(
        current: _stale,
        defaults: const InferenceSettings(),
        estimate: (s) async => e4b(s),
      );
      expect(result.nGpuLayers, 999);
      expect(result.kvCacheType, KvCacheType.q8_0);
    },
  );

  test('setups try MTP off and a 3-token draft only with an MTP head', () {
    const best = InferenceSettings(batchSize: 512, cpuThreads: 8);
    final plain = pcOptimizationSetups(best);
    final mtp = pcOptimizationSetups(best, mtpHead: true);
    expect(mtp.length, plain.length + 2);
    expect(plain.map((s) => s.draftModelId), everyElement(best.draftModelId));
    expect(mtp.map((s) => s.draftModelId), contains('mtp:off'));
    expect(mtp.map((s) => s.draftMaxTokens), contains(3));
  });

  test('optimization refuses incomplete memory estimates', () async {
    await expectLater(
      pcOptimizationDefaults(
        current: _stale,
        defaults: const InferenceSettings(),
        estimate: (_) async => {'layers': 24},
      ),
      throwsStateError,
    );
  });

  test('Q8 fallback is used only when F16 cannot fit even on CPU', () async {
    final result = await pcOptimizationDefaults(
      current: _stale,
      defaults: const InferenceSettings(),
      estimate: (s) async => {
        ..._estimate(s),
        'ramNeedMb': s.kvCacheType == KvCacheType.fp16 ? 20000 : 2048,
      },
    );
    expect(result.kvCacheType, KvCacheType.q8_0);
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'Optimize button ${cancel ? 'cancels without saving' : 'measures and applies safe defaults'}',
      (tester) async {
        final engine = _Engine()..gate = Completer<void>();
        final c = ProviderContainer(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            modelManagerProvider.overrideWith(_Models.new),
            llamaEstimatorProvider.overrideWithValue(_Estimator()),
            modelSpeedEngineProvider.overrideWithValue(engine),
          ],
        );
        addTearDown(c.dispose);
        final profiles = c.read(modelProfilesProvider.notifier);
        await profiles.ready;
        await profiles.set('test', {'temperature': 0.25, 'nGpuLayers': 3});
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: c,
            child: MaterialApp(
              theme: DesktopTheme.of(AccentChoice.amber, dark: true),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: ModelOptimizeSection(model: testModel, settings: _stale),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(engine.calls, 0);
        expect(c.read(settingsProvider).kvCacheType, KvCacheType.q8_0);
        await tester.tap(find.byKey(const Key('desktop-optimize')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(c.read(sessionBusyProvider), isTrue);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        if (cancel) {
          await tester.tap(find.text(AppLocalizationsEn().tuneCancel));
        } else {
          engine.gate!.complete();
        }
        await tester.pumpAndSettle();
        expect(c.read(sessionBusyProvider), isFalse);
        final model = profiles.of('test');
        expect(model['temperature'], 0.25);
        if (cancel) {
          expect(model['nGpuLayers'], 3);
          expect(c.read(settingsProvider).kvCacheType, KvCacheType.q8_0);
        } else {
          expect(model['nGpuLayers'], greaterThan(3));
          expect(model['kvCacheType'], 'fp16');
          expect(model['flashAttention'], isTrue);
          expect(model['draftModelId'], '');
          final global = c.read(settingsProvider);
          // The winner goes to this model's profile only: the app-wide
          // choices other models use are kept (audit P1-13).
          expect(global.explicitOverrides, contains('kvCacheType'));
          expect(global.kvCacheType, KvCacheType.q8_0);
          expect(global.explicitOverrides, contains('temperature'));
          expect(find.textContaining('Before: 100.0'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
