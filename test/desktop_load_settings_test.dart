import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/desktop/load_settings_dialog.dart';
import 'package:ondevice_llm/desktop/inspector_panel.dart';
import 'package:ondevice_llm/features/adapters/adapter_store.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/domain/settings_scope.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_sampling_variants_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_pages_2_test.dart' show TestSettings, TestModels, testModel;

class _Engine extends LlamaEngine {
  @override
  Future<Map<String, dynamic>> probe() async => {'supportsDFlash': true};

  @override
  Future<Map<String, dynamic>> adapterInfo(String path) async => {
    'keys': {'tokenizer.chat_template': '{{ messages }}'},
  };

  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => {'layers': 24, 'contextTrain': 4096};
}

class _Adapters extends AdaptersNotifier {
  @override
  AdaptersState build() {
    ready = Future.value();
    return const AdaptersState(
      attachments: {
        'test': [AdapterAttachment('large.gguf', 1)],
      },
    );
  }

  @override
  Future<List<({String path, double scale})>> resolved(String modelId) async =>
      [for (final a in state.of(modelId)) (path: a.adapterId, scale: a.scale)];

  void select(String path, double scale) {
    state = state.copyWith(
      attachments: {
        'test': [AdapterAttachment(path, scale)],
      },
    );
  }
}

class _AdapterEstimates extends _Engine {
  final requests = <List<({String path, double scale})>>[];

  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    requests.add(adapters);
    return {'layers': 24, 'contextTrain': 4096};
  }
}

/// Records the draft length every memory estimate was asked for.
class _DraftEstimates extends _Engine {
  final draftTokens = <int>[];

  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async {
    draftTokens.add(settings.draftMaxTokens);
    return super.estimate(
      modelPath: modelPath,
      settings: settings,
      mmprojPath: mmprojPath,
      adapters: adapters,
      draftModelPath: draftModelPath,
    );
  }
}

/// The card as it reads with the loaded model's 6 GB still on it.
class _FullCard extends _Engine {
  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => modelPath == 'loaded.gguf'
      ? {'vramNeedMb': 6000, 'ramNeedMb': 1000}
      : {
          'layers': 24,
          'gpuLayers': 25,
          'contextTrain': 4096,
          'vramNeedMb': 6800,
          'vramFreeMb': 1100,
          'vramTotalMb': 8192,
          'ramNeedMb': 2000,
          'ramPagedMb': 2048,
          'ramAvailableMb': 12000,
          'ramTotalMb': 32000,
        };
}

class _LoadedModels extends TestModels {
  @override
  ChatLoad? get loadedConfig => (
    modelId: 'test',
    modelPath: 'loaded.gguf',
    adapters: const [],
    settings: const InferenceSettings(),
    mmprojPath: null,
    draftModelPath: null,
  );
}

class _LargeContextSettings extends TestSettings {
  @override
  InferenceSettings build() => super.build().copyWith(contextSize: 32768);
}

class _RunningModels extends TestModels {
  final bool same;
  _RunningModels(this.same);

  @override
  ChatLoad? get loadedConfig => (
    modelId: same ? 'test' : 'other',
    modelPath: same ? 'test.gguf' : 'other.gguf',
    adapters: const [],
    settings: const InferenceSettings(contextSize: 32768),
    mmprojPath: null,
    draftModelPath: null,
  );
}

class _OccupiedCard extends _Engine {
  final bool tight;
  _OccupiedCard({this.tight = false});

  @override
  Future<Map<String, dynamic>> estimate({
    required String modelPath,
    required InferenceSettings settings,
    String? mmprojPath,
    List<({String path, double scale})> adapters = const [],
    String? draftModelPath,
  }) async => {
    'modelLoaded': false, // The estimator has its own unloaded runtime.
    'layers': 41,
    'gpuLayers': 0,
    'contextSize': 4096,
    'contextCap': 'memory',
    'contextTrain': 262144,
    'vramNeedMb': 2700,
    'vramFreeMb': 2700,
    'vramTotalMb': 2700,
    'ramNeedMb': tight ? 30000 : 18000,
    'ramAvailableMb': 8000,
    'ramTotalMb': 32768,
    'devices': [
      {'type': 'gpu', 'backend': 'CUDA', 'totalMb': 8192, 'freeMb': 2700},
    ],
  };
}

void main() {
  setUp(() => DesktopHost.active = true);
  tearDown(() => DesktopHost.active = false);

  testWidgets('adapter paths and scales reach estimates and cache keys (E09)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final estimator = _AdapterEstimates();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        adaptersProvider.overrideWith(_Adapters.new),
        llamaEngineProvider.overrideWithValue(estimator),
        llamaEstimatorProvider.overrideWithValue(estimator),
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
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDesktopLoadSettings(context, testModel),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(estimator.requests, [
      [(path: 'large.gguf', scale: 1.0)],
    ]);
    final adapters = container.read(adaptersProvider.notifier) as _Adapters;
    adapters.select('large.gguf', 0.5);
    await tester.pumpAndSettle();
    expect(estimator.requests.last, [(path: 'large.gguf', scale: 0.5)]);
    expect(estimator.requests, hasLength(2));
    adapters.select('other.gguf', 0.5);
    await tester.pumpAndSettle();
    expect(estimator.requests.last, [(path: 'other.gguf', scale: 0.5)]);
    expect(estimator.requests, hasLength(3));
    adapters.select('large.gguf', 1);
    await tester.pumpAndSettle();
    expect(estimator.requests, hasLength(3)); // Reuse this exact adapter set.
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'closing Load settings while MTP discovery waits is safe (P2-55)',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          llamaEngineProvider.overrideWithValue(_Engine()),
          llamaEstimatorProvider.overrideWithValue(_Engine()),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: DesktopTheme.of(AccentChoice.amber, dark: true),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDesktopLoadSettings(context, testModel),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final loaded in [false, true]) {
    testWidgets('the loaded model counts as free memory (loaded: $loaded)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(
            loaded ? _LoadedModels.new : TestModels.new,
          ),
          llamaEngineProvider.overrideWithValue(_Engine()),
          llamaEstimatorProvider.overrideWithValue(_FullCard()),
        ],
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
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
      expect(
        find.text(AppLocalizationsEn().desktopLoadSettingsPaged('2.0')),
        findsOneWidget,
      );
      // 1.1 GB free + the 6 GB the loaded model frees covers 6.8 GB.
      expect(
        find.text(AppLocalizationsEn().desktopLoadSettingsSpill('5.6')),
        loaded ? findsNothing : findsOneWidget,
      );
      expect(
        find.text(AppLocalizationsEn().desktopLoadSettingsFitsGpu),
        loaded ? findsOneWidget : findsNothing,
      );
    });
  }
  for (final scenario in [
    'same',
    'other',
    'changed',
    'cpu',
    'capped',
    'tight',
  ]) {
    testWidgets('occupied card admission: $scenario', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = _Engine()
        ..metrics = {
          'backend': 'CUDA / RTX 3070',
          'effectiveSettings': {
            'contextSize': scenario == 'capped' ? 16384 : 32768,
            'contextCap': scenario == 'capped' ? 'memory' : '',
            'contextTrain': 262144,
            'layers': 41,
            'gpuLayers': scenario == 'cpu' ? 0 : 41,
            'gpuExpertsOnCpu': scenario == 'same',
            'memoryNeedMb': 18000,
            'vramNeedMb': scenario == 'cpu' ? 0 : 6000,
          },
        };
      final c = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(_LargeContextSettings.new),
          modelManagerProvider.overrideWith(
            () => _RunningModels(scenario != 'other' && scenario != 'tight'),
          ),
          llamaEngineProvider.overrideWithValue(engine),
          llamaEstimatorProvider.overrideWithValue(
            _OccupiedCard(tight: scenario == 'tight'),
          ),
        ],
      );
      addTearDown(c.dispose);
      await c.read(modelProfilesProvider.notifier).ready;
      if (scenario == 'changed') {
        await c.read(modelProfilesProvider.notifier).set('test', {
          'offloadKv': false,
        });
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: c,
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
      final uncertain =
          scenario == 'other' || scenario == 'changed' || scenario == 'tight';
      expect(
        find.text(t.desktopLoadSettingsGpuNone),
        scenario == 'cpu' || scenario == 'tight'
            ? findsOneWidget
            : findsNothing,
      );
      expect(
        find.text(t.desktopLoadSettingsCapped('4K')),
        scenario == 'tight' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text(t.desktopLoadSettingsCapped('16K')),
        scenario == 'capped' ? findsOneWidget : findsNothing,
      );
      expect(
        find.text(t.desktopLoadSettingsLoadedNote),
        uncertain ? findsOneWidget : findsNothing,
      );
      expect(
        find.text(t.desktopLoadSettingsGpuLayers(41, 41)),
        !uncertain && scenario != 'cpu' ? findsOneWidget : findsNothing,
      );
      // Credit is capped at the 8 GB capacity, not the occupied 2.7 GB reading.
      expect(
        find.text(
          t.desktopLoadSettingsUsage(
            uncertain
                ? '2.6'
                : scenario == 'cpu'
                ? '0.0'
                : '5.9',
            scenario == 'cpu' ? '2.6' : '8.0',
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  test('VRAM reserve reaches the bridge load config and model profiles', () {
    final settings = InferenceSettings.fromJson({
      ...const InferenceSettings().toJson(),
      'vramReserveMb': 1536,
    });
    expect(settings.vramReserveMb, 1536);
    expect(settings.copyWith(vramReserveMb: 512).vramReserveMb, 512);
    expect(
      jsonDecode(LlamaEngine.loadConfig(settings: settings))['vramReserveMb'],
      1536,
    );
    expect(SettingsResolver.sanitize({'vramReserveMb': 2048}), {
      'vramReserveMb': 2048,
    });
    expect(SettingSpec.byKey('vramReserveMb')?.reloadRequired, isTrue);
  });

  testWidgets('answer variants apply and capture the dialog draft', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final c = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        llamaEngineProvider.overrideWithValue(_Engine()),
        llamaEstimatorProvider.overrideWithValue(_Engine()),
      ],
    );
    addTearDown(c.dispose);
    final variants = c.read(modelSamplingVariantsProvider.notifier);
    await variants.save('test', 'Focused', values: {'temperature': 0.2});
    final t = AppLocalizationsEn();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
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
    final projector = find.byKey(const Key('ttft-projector'));
    expect(tester.widget<SegmentedButton<String>>(projector).selected, {
      'auto',
    });
    expect(find.text(t.projectorDeviceHelp), findsOneWidget);
    await tester.tap(
      find.descendant(of: projector, matching: find.text(t.projectorCpu)),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<String>>(projector).selected, {'cpu'});
    final menu = find.byKey(const Key('desktop-model-preset-menu'));
    await tester.scrollUntilVisible(
      menu,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(menu);
    await tester.pumpAndSettle();
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckedPopupMenuItem<(int, String?)>).last);
    await tester.pumpAndSettle();
    final temp = find.byWidgetPredicate(
      (w) => w is DesktopSlider && w.label == t.desktopInspectorTemperature,
    );
    await tester.ensureVisible(temp);
    expect(tester.widget<DesktopSlider>(temp).value, 0.2);
    tester.widget<DesktopSlider>(temp).onChanged(0.4);
    await tester.pumpAndSettle();
    expect(c.read(modelProfilesProvider)['test']!['temperature'], 0.2);
    await tester.scrollUntilVisible(
      menu,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    // Clear of the dialog's header.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('desktop-model-preset-modified')),
      findsOneWidget,
    );
    await tester.tap(menu);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.desktopModelPresetUpdate));
    await tester.pumpAndSettle();
    expect(variants.of('test').selected!.values['temperature'], 0.4);
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(c.read(modelProfilesProvider)['test']!['temperature'], 0.4);
    expect(c.read(modelProfilesProvider)['test']!['projectorDevice'], 'cpu');
  });

  test('prompt template survives settings JSON and the profile resolver', () {
    const template = '{% for m in messages %}{{ m.content }}{% endfor %}';
    final settings = const InferenceSettings().copyWith(chatTemplate: template);
    expect(
      InferenceSettings.fromJson(settings.toJson()).chatTemplate,
      template,
    );
    final resolved = SettingsResolver.resolve(
      global: const InferenceSettings(),
      model: {'chatTemplate': template},
    );
    expect(resolved.effective.chatTemplate, template);
    expect(resolved.reloadKeys, contains('chatTemplate'));
    expect(
      jsonDecode(
        LlamaEngine.loadConfig(settings: resolved.effective),
      )['chatTemplate'],
      template,
    );
    expect(const InferenceSettings().chatTemplate, isEmpty);
  });

  testWidgets(
    'embedded template is read-only; override persists and reset restores embedded',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          llamaEngineProvider.overrideWithValue(_Engine()),
          llamaEstimatorProvider.overrideWithValue(_Engine()),
        ],
      );
      addTearDown(container.dispose);
      await container.read(modelProfilesProvider.notifier).ready;
      final t = AppLocalizationsEn();
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
      Future<void> open() async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('desktop-prompt-template')),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }

      final editor = find.byKey(const Key('desktop-prompt-template'));
      await open();
      expect(tester.widget<TextField>(editor).readOnly, isTrue);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        '{{ messages }}',
      );
      await tester.tap(find.text(t.desktopPromptTemplateOverride));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editor).readOnly, isFalse);
      await tester.enterText(editor, 'CUSTOM {{ messages }}');
      await tester.tap(find.text(t.save));
      await tester.pumpAndSettle();
      expect(
        container.read(modelProfilesProvider)['test']?['chatTemplate'],
        'CUSTOM {{ messages }}',
      );
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('model_profiles_v1'),
        contains('CUSTOM {{ messages }}'),
      );
      await open();
      expect(
        tester.widget<TextField>(editor).controller!.text,
        'CUSTOM {{ messages }}',
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('desktop-prompt-template')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text(t.desktopPromptTemplateReset));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(editor).readOnly, isTrue);
      expect(
        tester.widget<TextField>(editor).controller!.text,
        '{{ messages }}',
      );
      await tester.tap(find.text(t.save));
      await tester.pumpAndSettle();
      expect(
        container.read(modelProfilesProvider)['test']?['chatTemplate'],
        '',
      );

      // How the model answers is saved with it too.
      final temperature = find.byKey(const Key('desktop-temperature'));
      Future<void> showTemperature() async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          temperature,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
      }

      await showTemperature();
      tester
          .widget<Slider>(
            find.descendant(of: temperature, matching: find.byType(Slider)),
          )
          .onChanged!(0.3);
      await tester.pumpAndSettle();
      expect(tester.widget<DesktopSlider>(temperature).source, 'model');
      await tester.tap(find.text(t.save));
      await tester.pumpAndSettle();
      expect(
        container.read(modelProfilesProvider)['test']?['temperature'],
        0.3,
      );
      await showTemperature();
      expect(tester.widget<DesktopSlider>(temperature).value, 0.3);
      await tester.tap(find.text(t.desktopLoadSettingsReset));
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.save));
      await tester.pumpAndSettle();
      expect(
        container.read(modelProfilesProvider)['test'],
        isNot(contains('temperature')),
      );
    },
  );
  testWidgets('advanced groups persist and reset a model override', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        llamaEngineProvider.overrideWithValue(_Engine()),
        llamaEstimatorProvider.overrideWithValue(_Engine()),
      ],
    );
    addTearDown(container.dispose);
    final t = AppLocalizationsEn();
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
    Future<void> open() async {
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    final field = find.byKey(const Key('desktopDeep-microBatchSize'));
    for (final id in ['load', 'sampling', 'speculative', 'memory']) {
      await open();
      final group = find.byKey(Key('desktopDeep-group-$id'));
      await tester.scrollUntilVisible(
        group,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(tester.widget<ExpansionTile>(group).initiallyExpanded, isFalse);
      await tester.tap(
        find.descendant(of: group, matching: find.byType(ListTile)).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          Key(
            'desktopDeep-${switch (id) {
              'load' => 'microBatchSize',
              'sampling' => 'seed',
              'speculative' => 'draftMaxTokens',
              _ => 'promptCache',
            }}',
          ),
        ),
        findsOneWidget,
      );
      for (final key in switch (id) {
        'load' => [
          'useMmap',
          'useMlock',
          'mainGpu',
          'splitMode',
          'offloadKv',
          'swaFull',
          'nCpuMoe',
          'moeCacheSizeMb',
          'moeCacheCpuShare',
          'expertsUsed',
        ],
        'sampling' => ['logitBias'],
        'memory' => ['keepTokens', 'contextOverflow'],
        _ => <String>[],
      }) {
        expect(find.byKey(Key('desktopDeep-$key')), findsOneWidget);
      }
      await tester.tap(find.byTooltip(t.cancel));
      await tester.pumpAndSettle();
    }
    await open();
    final load = find.byKey(const Key('desktopDeep-group-load'));
    await tester.scrollUntilVisible(
      load,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: load, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextFormField)),
      '256',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(
      container.read(modelProfilesProvider)['test']?['microBatchSize'],
      256,
    );
    await open();
    await tester.scrollUntilVisible(
      load,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: load, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(field);
    expect(find.text('256'), findsWidgets);
    await tester.ensureVisible(
      find.byKey(const Key('desktopDeep-reset-microBatchSize')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('desktopDeep-reset-microBatchSize')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(
      container.read(modelProfilesProvider)['test'],
      isNot(contains('microBatchSize')),
    );
  });

  testWidgets('a new draft length asks for a fresh memory estimate (E10)', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final estimator = _DraftEstimates();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        llamaEngineProvider.overrideWithValue(estimator),
        llamaEstimatorProvider.overrideWithValue(estimator),
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
    expect(estimator.draftTokens, hasLength(1));
    final group = find.byKey(const Key('desktopDeep-group-speculative'));
    await tester.scrollUntilVisible(
      group,
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: group, matching: find.byType(ListTile)).first,
    );
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('desktopDeep-draftMaxTokens'));
    await tester.ensureVisible(field);
    await tester.enterText(
      find.descendant(of: field, matching: find.byType(TextFormField)),
      '3',
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    // Draft length changes n_rs_seq and the output limits, so caching the
    // previous estimate would show the wrong memory use.
    expect(estimator.draftTokens, hasLength(2));
    expect(estimator.draftTokens.last, 3);
  });
}
