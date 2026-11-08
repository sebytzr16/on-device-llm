import 'package:ondevice_llm/desktop/history_store.dart';
import 'package:drift/native.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/desktop/compare_page.dart';
import 'package:ondevice_llm/desktop/desktop_theme.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

import 'advanced_pages_2_test.dart' show TestSettings;

const _first = ModelInfo(
  id: 'first',
  displayName: 'First',
  fileName: 'first.gguf',
  sizeBytes: 100,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: 'first.gguf',
);
const _second = ModelInfo(
  id: 'second',
  displayName: 'Second',
  fileName: 'second.gguf',
  sizeBytes: 100,
  family: ModelFamily.qwen,
  quantization: ModelQuantization.q4_k_m,
  isDownloaded: true,
  localPath: 'second.gguf',
);

class _Manager extends ModelManagerNotifier {
  static int auditContext = 4096;
  static int auditLoads = 0;
  static double auditTemperature = 0.7;
  static final residentAtLoad = <int>[];
  static final residents = <_Engine>{};
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(catalog: [_first, _second]);
  }

  @override
  Future<void> loadServed(
    ModelInfo info,
    LlamaEngine engine, {
    bool vision = false,
  }) async {
    final owned = engine as _Engine;
    final config = LlamaEngine.loadConfig(settings: servedSettings(info));
    if (owned.loaded && owned.config == config) return;
    residentAtLoad.add(residents.where((e) => e != owned && e.loaded).length);
    _Manager.auditLoads++;
    owned.config = config;
    owned.loaded = true;
    residents.add(owned);
  }

  @override
  InferenceSettings servedSettings(ModelInfo info) => InferenceSettings(
    contextSize: auditContext,
    temperature: auditTemperature,
  );
}

class _ChatManager extends _Manager {
  @override
  ModelManagerState build() => super.build().copyWith(loadedModelId: _first.id);
}

class _MemoryManager extends _Manager {
  @override
  Future<void> loadServed(
    ModelInfo info,
    LlamaEngine engine, {
    bool vision = false,
  }) async {
    throw const NotEnoughMemoryException('This model needs more memory.');
  }
}

class _Engine extends LlamaEngine {
  final String name;
  final List<String> starts;
  bool loaded = false;
  bool busy = false;
  bool cancelled = false;
  bool disposed = false;
  bool unloaded = false;
  String? config;
  InferenceSettings? generatedSettings;
  final gate = Completer<void>();
  final progress = StreamController<double?>.broadcast();

  _Engine(this.name, this.starts) {
    metrics = {'firstTokenMs': 12, 'tokensPerSecond': 30, 'tokens': 2};
  }

  @override
  bool get isLoaded => loaded;
  @override
  bool get isBusy => busy;
  @override
  Stream<double?> get loadProgressChanges => progress.stream;
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<dynamic> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    busy = true;
    generatedSettings = settings;
    starts.add(name);
    yield '$name one';
    await gate.future;
    if (!cancelled) yield ' two';
    busy = false;
  }

  @override
  void cancel() {
    cancelled = true;
    if (!gate.isCompleted) gate.complete();
  }

  @override
  Future<void> unload() {
    unloaded = true;
    loaded = false;
    return SynchronousFuture<void>(null);
  }

  @override
  void dispose() {
    disposed = true;
  }

  void finish() {
    if (!gate.isCompleted) gate.complete();
  }
}

void main() {
  final t = AppLocalizationsEn();
  final starts = <String>[];
  final created = <_Engine>[];
  late _Engine chat;

  Future<void> mount(
    WidgetTester tester, {
    bool chatLoaded = false,
    bool chatReserved = false,
    bool memoryError = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    starts.clear();
    created.clear();
    _Manager.auditLoads = 0;
    _Manager.auditContext = 4096;
    _Manager.auditTemperature = 0.7;
    _Manager.residentAtLoad.clear();
    _Manager.residents.clear();
    chat = _Engine('chat', starts)..loaded = chatLoaded;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final database = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          sessionBusyProvider.overrideWith((ref) => chatReserved),
          modelManagerProvider.overrideWith(
            memoryError
                ? _MemoryManager.new
                : chatLoaded
                ? _ChatManager.new
                : _Manager.new,
          ),
          settingsProvider.overrideWith(TestSettings.new),
          llamaEngineProvider.overrideWithValue(chat),
          engineFactoryProvider.overrideWithValue(() {
            final engine = _Engine('own${created.length}', starts);
            created.add(engine);
            return engine;
          }),
        ],
        child: MaterialApp(
          theme: DesktopTheme.of(AccentChoice.amber, dark: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: DesktopComparePage()),
        ),
      ),
    );
    await tester.pump();
    tester
        .widget<DropdownButton<String>>(
          find.byKey(const Key('desktopCompareModel0')),
        )
        .onChanged!(_first.id);
    await tester.pump();
    tester
        .widget<DropdownButton<String>>(
          find.byKey(const Key('desktopCompareModel1')),
        )
        .onChanged!(_second.id);
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('desktopComparePrompt')),
      'Explain this',
    );
    await tester.pump();
  }

  Future<void> finishRun(WidgetTester tester) async {
    for (var frame = 0; frame < 30; frame++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      for (final engine in created) {
        engine.finish();
      }
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text(t.desktopCompareRun).evaluate().isNotEmpty) return;
    }
    fail(
      'Compare did not finish: $starts ${created.map((e) => '${e.name}:loaded=${e.loaded},busy=${e.busy},unloaded=${e.unloaded}')}',
    );
  }

  testWidgets(
    'streams both answers in order and releases owned engines on leave',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text(t.desktopCompareRun));
      await tester.pump();
      expect(starts, ['own0']);
      expect(find.textContaining('own0 one'), findsWidgets);
      created[0].finish();
      await tester.pump();
      await tester.pump();
      expect(starts, ['own0', 'own1']);
      created[1].finish();
      await tester.pump();
      expect(find.textContaining('own1 one two'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      addTearDown(() {
        expect(created.every((e) => e.unloaded && e.disposed), isTrue);
      });
    },
  );

  testWidgets(
    'history restores both answers and stats read-only, then Run unlocks',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text(t.desktopCompareRun));
      await finishRun(tester);
      final page = find.byType(DesktopComparePage);
      final container = ProviderScope.containerOf(tester.element(page));
      final store = container.read(compareHistoryStoreProvider);
      final saved = await tester.runAsync(() => store.list());
      expect(saved, hasLength(1));
      expect(saved!.single.data['prompt'], 'Explain this');
      expect(
        (saved.single.data['sides'] as List).first['answer'],
        contains('own0'),
      );
      await tester.tap(find.text(t.historyTitle));
      await tester.runAsync(
        () => container.read(compareHistoryProvider.future),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('desktopComparePrompt')))
            .readOnly,
        true,
      );
      expect(find.textContaining('own0 one two'), findsWidgets);
      expect(find.textContaining('own1 one two'), findsWidgets);
      await tester.tap(find.text(t.desktopCompareRun));
      await tester.pump();
      expect(find.text(t.historyReadOnly), findsNothing);
      await finishRun(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('side by side starts both and Stop cancels both', (tester) async {
    await mount(tester);
    await tester.tap(find.text(t.desktopCompareParallel));
    await tester.pump();
    await tester.tap(find.text(t.desktopCompareRun));
    await tester.pump();
    expect(starts, ['own0', 'own1']);
    await tester.tap(find.text(t.desktopCompareStop));
    await tester.pump();
    expect(created.every((e) => e.cancelled), isTrue);
  });

  testWidgets('reuses the idle chat engine without disposing it', (
    tester,
  ) async {
    await mount(tester, chatLoaded: true);
    await tester.tap(find.text(t.desktopCompareRun));
    await tester.pump();
    expect(starts, ['chat']);
    chat.finish();
    await tester.pump();
    await tester.pump();
    expect(starts, ['chat', 'own0']);
    created.single.finish();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(chat.disposed, isFalse);
    expect(chat.unloaded, isFalse);
    addTearDown(() => expect(created.every((e) => e.disposed), isTrue));
  });

  testWidgets('loads a separate copy while the chat engine is busy', (
    tester,
  ) async {
    await mount(tester, chatLoaded: true);
    chat.busy = true;
    await tester.tap(find.text(t.desktopCompareRun));
    await tester.pump();
    expect(starts, ['own0']);
    expect(chat.cancelled, isFalse);
    created[0].finish();
    await tester.pump();
    await tester.pump();
    created[1].finish();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(chat.disposed, isFalse);
  });

  testWidgets('shows a readable memory load error', (tester) async {
    await mount(tester, memoryError: true);
    await tester.tap(find.text(t.desktopCompareRun));
    await tester.pump();
    expect(find.text('This model needs more memory.'), findsNWidgets(2));
    addTearDown(() => expect(created.every((e) => e.disposed), isTrue));
  });

  testWidgets('C01: retained engines revalidate canonical load settings', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text(t.desktopCompareParallel));
    await tester.pump();
    await tester.tap(find.text(t.desktopCompareRun));
    await finishRun(tester);
    expect(_Manager.auditLoads, 2);
    expect(created.every((e) => !e.disposed), isTrue);
    await tester.tap(find.text(t.desktopCompareRun));
    await finishRun(tester);
    expect(_Manager.auditLoads, 2, reason: 'Unchanged settings retain loads');
    _Manager.auditTemperature = 0.2;
    await tester.tap(find.text(t.desktopCompareRun));
    await finishRun(tester);
    expect(_Manager.auditLoads, 2, reason: 'Sampling changes retain loads');
    expect(created.every((e) => !e.unloaded), isTrue);
    expect(
      created.every((e) => e.generatedSettings?.temperature == 0.2),
      isTrue,
    );
    _Manager.auditContext = 8192;
    await tester.tap(find.text(t.desktopCompareRun));
    await tester.pump();
    await tester.pump();
    expect(created, hasLength(2), reason: 'Exercise retained engines');
    expect(_Manager.auditLoads, 4, reason: 'Both retained engines reload');
    expect(
      created.every(
        (e) =>
            e.config ==
            LlamaEngine.loadConfig(
              settings: const InferenceSettings(
                contextSize: 8192,
                temperature: 0.2,
              ),
            ),
      ),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  for (final parallelFirst in [false, true]) {
    testWidgets(
      'C02: sequential owns one model after parallel=$parallelFirst',
      (tester) async {
        await mount(tester);
        if (parallelFirst) {
          await tester.tap(find.text(t.desktopCompareParallel));
          await tester.pump();
        }
        await tester.tap(find.text(t.desktopCompareRun));
        await finishRun(tester);
        if (parallelFirst) {
          await tester.tap(find.text(t.desktopCompareSequential));
          await tester.pump();
        }
        _Manager.residentAtLoad.clear();
        for (var run = 0; run < 2; run++) {
          await tester.tap(find.text(t.desktopCompareRun));
          await finishRun(tester);
        }
        expect(_Manager.residentAtLoad, isNotEmpty);
        expect(
          _Manager.residentAtLoad,
          everyElement(0),
          reason: 'Release other owned engine before every sequential load',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      },
    );
  }

  // C02: Sequential compare unloads first owned engine before loading second
  testWidgets(
    'AUDIT: Sequential compare unloads first owned engine before loading second',
    (tester) async {
      await mount(tester);
      await tester.tap(find.text(t.desktopCompareRun));
      await tester.pump();
      // First engine starts
      expect(starts, ['own0']);
      created[0].finish();
      await tester.pump();
      await tester.pump();
      // After first completes in sequential mode, its owned engine should be unloaded before second loads
      expect(
        created[0].unloaded,
        isTrue,
        reason:
            'First owned engine should be unloaded before second loads in sequential mode',
      );
      // Second engine starts
      expect(starts, ['own0', 'own1']);
      created[1].finish();
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  // C05: Compare does not borrow a reserved chat runtime
  testWidgets('AUDIT: Compare does not borrow a reserved chat runtime', (
    tester,
  ) async {
    await mount(tester, chatLoaded: true, chatReserved: true);
    await tester.tap(find.text(t.desktopCompareRun));
    await tester.pump();
    final firstEngine = starts.first;
    chat.finish();
    await tester.pump();
    await tester.pump();
    for (final e in created) {
      e.finish();
    }
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(
      firstEngine,
      isNot('chat'),
      reason:
          'Chat owns the runtime while awaiting helpers even when native decoding is idle',
    );
  });
}
