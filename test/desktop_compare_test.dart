import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(catalog: [_first, _second]);
  }

  @override
  Future<void> loadServed(ModelInfo info, LlamaEngine engine) async {
    (engine as _Engine).loaded = true;
  }

  @override
  InferenceSettings servedSettings(ModelInfo info) => const InferenceSettings();
}

class _ChatManager extends _Manager {
  @override
  ModelManagerState build() => super.build().copyWith(loadedModelId: _first.id);
}

class _MemoryManager extends _Manager {
  @override
  Future<void> loadServed(ModelInfo info, LlamaEngine engine) async {
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
  final gate = Completer<void>();

  _Engine(this.name, this.starts) {
    metrics = {'firstTokenMs': 12, 'tokensPerSecond': 30, 'tokens': 2};
  }

  @override
  bool get isLoaded => loaded;
  @override
  bool get isBusy => busy;
  @override
  Stream<double?> get loadProgressChanges => const Stream.empty();
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
    bool memoryError = false,
  }) async {
    starts.clear();
    created.clear();
    chat = _Engine('chat', starts)..loaded = chatLoaded;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
}
