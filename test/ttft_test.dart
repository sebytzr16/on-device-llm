import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/run_details_sheet.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/cpu_cores.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/desktop/model_speed_results_provider.dart';
import 'package:ondevice_llm/desktop/tune_benchmark_run.dart';
import 'package:ondevice_llm/features/chat/domain/entities/turn_run.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/run_timing_rows.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/presentation/widgets/settings_labels.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'advanced_pages_2_test.dart' show testModel;
import 'package:ondevice_llm/features/presets/domain/preset.dart';

void main() {
  testWidgets('timing breakdown appears in run details', (tester) async {
    final run = TurnRun(
      settings: const {},
      engine: const {'warmupMs': 200, 'projectorDevice': 'cpu'},
      metrics: const {
        'lifecycle': [
          {'stage': 'preparing', 'elapsedMs': 0},
          {'stage': 'reading', 'elapsedMs': 50},
          {'stage': 'writing', 'elapsedMs': 700},
        ],
        'beginMs': 20,
        'prefillMs': 500,
        'checkpointMs': 30,
        'promptTokens': 300,
        'cachedPromptTokens': 100,
      },
      modelId: 'test',
      modelName: 'Model',
      presetId: 'general',
      presetName: 'General',
      sources: 0,
      at: DateTime.utc(2026),
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold();
          },
        ),
      ),
    );
    unawaited(showRunDetailsSheet(context, run));
    await tester.pumpAndSettle();
    for (final label in [
      'Send to first text',
      'App preparation',
      'Prompt setup',
      'Prompt reading',
      'Checkpoints',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('500 ms · 400.0 tok/s'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Warm-up'),
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('run-details')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Vision projector'), findsOneWidget);
    expect(find.text('System memory'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  setUp(() {
    final logical = CpuCores.logical, physical = CpuCores.physical;
    final query = CpuCores.query;
    final desktop = DesktopHost.active;
    addTearDown(() {
      CpuCores.logical = logical;
      CpuCores.physical = physical;
      CpuCores.query = query;
      DesktopHost.active = desktop;
    });
    CpuCores.logical = () => 16;
    CpuCores.physical = 8;
    CpuCores.query = () => null;
  });
  test(
    'desktop uses physical cores with or without a GPU; phone unchanged',
    () {
      const cpu = InferenceSettings(backend: GpuBackend.cpu);
      const gpu = InferenceSettings(backend: GpuBackend.cuda);
      DesktopHost.active = true;
      expect(cpu.effectiveThreads, 8);
      expect(cpu.effectiveBatchThreads, 8);
      expect(gpu.effectiveThreads, 8);
      expect(gpu.effectiveBatchThreads, 8);
      const auto = InferenceSettings();
      expect(auto.effectiveThreads, 8);
      expect(auto.copyWith(nGpuLayers: 0).effectiveThreads, 8);
      expect(threadsLabel(cpu), 'Auto (8)');
      expect(cpu.copyWith(cpuThreads: 12).effectiveBatchThreads, 12);
      expect(cpu.copyWith(batchThreads: 3).effectiveBatchThreads, 3);
      DesktopHost.active = false;
      expect(cpu.effectiveThreads, 6);
      expect(cpu.effectiveBatchThreads, 16);
      expect(gpu.effectiveThreads, 4);
      expect(auto.effectiveThreads, 6);
      CpuCores.physical = 2;
      expect(cpu.effectiveThreads, 6);
      expect(cpu.effectiveBatchThreads, 16);
    },
  );
  test('desktop fallback and clamps use injected logical counts', () {
    DesktopHost.active = true;
    CpuCores.physical = null;
    const cpu = InferenceSettings(backend: GpuBackend.cpu);
    for (final (logical, expected) in [
      (16, 8),
      (8, 4),
      (6, 6),
      (2, 2),
      (64, 16),
    ]) {
      CpuCores.logical = () => logical;
      expect(cpu.effectiveThreads, expected);
      expect(cpu.effectiveBatchThreads, expected);
    }
    CpuCores.physical = 24;
    expect(cpu.effectiveBatchThreads, 16);
  });
  test('projector survives profile resolution and changes load shape', () {
    DesktopHost.active = true;
    const initial = InferenceSettings();
    expect(initial.projectorDevice, 'auto');
    final requested = initial.copyWith(projectorDevice: 'cpu');
    final restored = InferenceSettings.fromJson(requested.toJson());
    expect(restored.projectorDevice, 'cpu');
    expect(requested.explicitOverrides, contains('projectorDevice'));
    expect(
      InferenceSettings.fromJson({'projectorDevice': 'bad'}).projectorDevice,
      'auto',
    );
    final resolved = SettingsResolver.resolve(
      global: initial,
      model: {'projectorDevice': 'gpu'},
    );
    expect(resolved.effective.projectorDevice, 'gpu');
    expect(resolved.reloadKeys, contains('projectorDevice'));
    expect(SettingSpec.byKey('projectorDevice')!.reloadRequired, true);
    expect(
      jsonDecode(LlamaEngine.loadConfig(settings: restored))['projectorDevice'],
      'cpu',
    );
    expect(
      LlamaEngine.loadConfig(settings: initial),
      isNot(LlamaEngine.loadConfig(settings: restored)),
    );
    for (final s in [requested, initial.copyWith(expertsUsed: 4)]) {
      expect(modelSpeedShape(s), isNot(modelSpeedShape(initial)));
    }
    expect(
      TuneBenchmarkRun.receiptSettings(
        requested.copyWith(expertsUsed: 4).toJson(),
      ),
      containsPair('projectorDevice', 'cpu'),
    );
    expect(TuneBenchmarkRun.receiptSettings({'expertsUsed': 4}), {
      'expertsUsed': 4,
    });
  });
  test('timing rows use first lifecycle stages and uncached prompt tokens', () {
    final t = AppLocalizationsEn();
    final metrics = <String, dynamic>{
      'lifecycle': [
        {'stage': 'preparing', 'elapsedMs': 0},
        {'stage': 'researching', 'elapsedMs': 120},
        {'stage': 'reading', 'elapsedMs': 180},
        {'stage': 'writing', 'elapsedMs': 950},
        {'stage': 'reading', 'elapsedMs': 1000},
        {'stage': 'writing', 'elapsedMs': 1200},
      ],
      'beginMs': 25.4,
      'prefillMs': 500,
      'checkpointMs': 0,
      'firstTokenFromBeginMs': 830,
      'promptTokens': 300,
      'cachedPromptTokens': 100,
      'effectiveSettings': {'warmupMs': 250, 'projectorDevice': 'cpu'},
    };
    expect(runTimingRows(t, metrics), [
      ('App preparation', '120 ms'),
      ('Send to first text', '950 ms'),
      ('Prompt setup', '25 ms'),
      ('Prompt reading', '500 ms · 400.0 tok/s'),
      ('Checkpoints', '0 ms'),
    ]);
    expect(engineTimingRows(t, metrics['effectiveSettings']), [
      ('Warm-up', '250 ms'),
      ('Vision projector', 'System memory'),
    ]);
    final run = TurnRun.capture(
      settings: const InferenceSettings(),
      preset: Preset.general,
      model: testModel,
      metrics: metrics,
      sources: 0,
    );
    final restored = TurnRun.decode(run.encode())!;
    for (final key in [
      'beginMs',
      'prefillMs',
      'checkpointMs',
      'firstTokenFromBeginMs',
    ]) {
      expect(restored.metrics[key], metrics[key]);
    }
    expect(restored.engine['warmupMs'], 250);
  });
  test('timing labels retain French and Spanish accents', () {
    expect(
      stringsFor('fr').runAppPreparation,
      'Pr\u00e9paration de l\u2019application',
    );
    expect(
      stringsFor('es').runAppPreparation,
      'Preparaci\u00f3n de la aplicaci\u00f3n',
    );
  });
  test('older and zero-duration runs omit unavailable values and rates', () {
    final t = AppLocalizationsEn();
    expect(runTimingRows(t, {}), isEmpty);
    expect(engineTimingRows(t, {}), isEmpty);
    expect(runTimingRows(t, {'prefillMs': 0, 'promptTokens': 3}), [
      ('Prompt reading', '0 ms'),
    ]);
    expect(engineTimingRows(t, {'projectorDevice': 'gpu'}), [
      ('Vision projector', 'Video memory'),
    ]);
  });
}
