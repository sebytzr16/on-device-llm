import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/island/status_island.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/models/data/last_model_store.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/effective_settings_provider.dart';
import 'package:ondevice_llm/features/presets/presentation/providers/presets_provider.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'chat_test.dart' show testModel, TestEngine;
import 'package:ondevice_llm/features/adapters/adapter_store.dart';

class _Adapters extends AdaptersNotifier {
  @override
  AdaptersState build() {
    ready = Future.value();
    return const AdaptersState();
  }
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState();
  }

  void chatLoaded() =>
      state = state.copyWith(catalog: [testModel], loadedModelId: testModel.id);
  void loaded() => state = state.copyWith(loadedModelId: 'manual');
  void omitCatalog() => state = state.copyWith(catalog: []);
  void loading() => state = state.copyWith(isLoadingModel: true);
}

class _Settings extends SettingsNotifier {
  final gate = Completer<void>();
  @override
  InferenceSettings build() {
    ready = gate.future;
    return const InferenceSettings();
  }

  void useCpu() =>
      state = state.copyWith(backend: GpuBackend.cpu, speculationMode: 'off');
  void remote(bool value) => state = state.copyWith(remoteEnabled: value);
}

class _Profiles extends ModelProfilesNotifier {
  final gate = Completer<void>();
  @override
  Map<String, Map<String, dynamic>> build() {
    ready = gate.future;
    return const {};
  }
}

class _Presets extends PresetsNotifier {
  final gate = Completer<void>();
  @override
  PresetsState build() {
    ready = gate.future;
    return const PresetsState();
  }
}

class _Chat extends ChatNotifier {
  @override
  ChatState build() => const ChatState();
  void generating() => state = state.copyWith(isGenerating: true);
}

class _Database extends AppDatabase {
  _Database() : super.forTesting(NativeDatabase.memory());
  Completer<void>? readGate;
  final reading = Completer<void>();
  @override
  Future<Model?> getModel(String id) async {
    if (readGate != null) {
      if (!reading.isCompleted) reading.complete();
      await readGate!.future;
    }
    return super.getModel(id);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer c;
  late _Database db;
  late _Models manager;
  late _Settings settings;
  late _Profiles profiles;
  late _Presets presets;
  late int loads;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = _Database();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        llamaEngineProvider.overrideWithValue(TestEngine()),
        adaptersProvider.overrideWith(_Adapters.new),
        modelManagerProvider.overrideWith(_Models.new),
        settingsProvider.overrideWith(_Settings.new),
        modelProfilesProvider.overrideWith(_Profiles.new),
        presetsProvider.overrideWith(_Presets.new),
        chatProvider.overrideWith(_Chat.new),
      ],
    );
    manager = c.read(modelManagerProvider.notifier) as _Models;
    settings = c.read(settingsProvider.notifier) as _Settings;
    profiles = c.read(modelProfilesProvider.notifier) as _Profiles;
    presets = c.read(presetsProvider.notifier) as _Presets;
    await manager.save(testModel);
    await LastModelStore.remember(testModel.id);
    loads = 0;
    c.read(engineHandoffProvider.notifier).state = (_) async {
      loads++;
      expect(await LastModelStore.read(), isNull);
      throw StateError(
        'Not enough free memory for this model: it needs about 4096 MB; 128 MB is free',
      );
    };
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  void ready() {
    settings.gate.complete();
    profiles.gate.complete();
    presets.gate.complete();
  }

  test(
    'restore waits for settings, profiles and presets; failure is one notice',
    () async {
      final restore = manager.restoreLastModel();
      await pumpEventQueue();
      expect(loads, 0);
      settings.gate.complete();
      await pumpEventQueue();
      expect(loads, 0);
      profiles.gate.complete();
      await pumpEventQueue();
      expect(loads, 0);
      presets.gate.complete();
      await restore;
      expect(loads, 1);
      expect(c.read(modelManagerProvider).error, isNull);
      // The silent start-up load still says why it failed: the chat's error
      // card is not the place for it (release review 1.8.0 #7).
      final toast = c.read(islandProvider).toast;
      expect(toast?.tone, IslandTone.warning);
      expect(toast?.text, stringsFor('').notEnoughMemory(4096, 128));
      expect(c.read(islandProvider).activity, isNull);
      expect(await LastModelStore.read(), isNull);
    },
  );
  test(
    'successful restore remembers the model again and is attempted once',
    () async {
      final engine = TestEngine();
      // Use the same successful load pipeline as an explicit model choice.
      c.dispose();
      c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          adaptersProvider.overrideWith(_Adapters.new),
          modelManagerProvider.overrideWith(_Models.new),
          settingsProvider.overrideWith(_Settings.new),
          modelProfilesProvider.overrideWith(_Profiles.new),
          presetsProvider.overrideWith(_Presets.new),
          chatProvider.overrideWith(_Chat.new),
          llamaEngineProvider.overrideWithValue(engine),
        ],
      );
      manager = c.read(modelManagerProvider.notifier) as _Models;
      settings = c.read(settingsProvider.notifier) as _Settings;
      profiles = c.read(modelProfilesProvider.notifier) as _Profiles;
      presets = c.read(presetsProvider.notifier) as _Presets;
      settings.useCpu();
      ready();
      await manager.restoreLastModel();
      await pumpEventQueue();
      expect(c.read(modelManagerProvider).loadedModelId, testModel.id);
      expect(engine.loadedWith?.backend, GpuBackend.cpu);
      expect(await LastModelStore.read(), testModel.id);
      manager.loaded();
      await manager.restoreLastModel();
      expect(c.read(modelManagerProvider).loadedModelId, 'manual');
    },
  );

  test('the startup restore never asks and keeps web research off', () async {
    var prompts = 0;
    final engine = TestEngine();
    c.dispose();
    c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        adaptersProvider.overrideWith(_Adapters.new),
        modelManagerProvider.overrideWith(_Models.new),
        settingsProvider.overrideWith(_Settings.new),
        modelProfilesProvider.overrideWith(_Profiles.new),
        presetsProvider.overrideWith(_Presets.new),
        chatProvider.overrideWith(_Chat.new),
        llamaEngineProvider.overrideWithValue(engine),
        webResearchConfirmationProvider.overrideWithValue(() async {
          prompts++;
          return false;
        }),
      ],
    );
    manager = c.read(modelManagerProvider.notifier) as _Models;
    settings = c.read(settingsProvider.notifier) as _Settings;
    profiles = c.read(modelProfilesProvider.notifier) as _Profiles;
    presets = c.read(presetsProvider.notifier) as _Presets;
    settings.useCpu();
    ready();
    // The restored model's profile turns web research on: the silent
    // start-up load must not ask with no user action and stays local
    // (review 2026-11-20 finding 2).
    await profiles.set(testModel.id, {'webMode': 'auto'});
    await manager.restoreLastModel();
    expect(prompts, 0);
    expect(engine.loadedWith?.webMode, WebMode.off);
    expect(c.read(modelManagerProvider).loadedModelId, testModel.id);
  });

  test(
    'Compare reloads the previous chat model through its normal loader',
    () async {
      ready();
      settings.useCpu();
      c.read(engineHandoffProvider.notifier).state = null;
      manager.chatLoaded();
      final resume = await manager.suspendChatForCompare();
      expect(c.read(modelManagerProvider).loadedModelId, isNull);
      await resume!();
      expect(c.read(modelManagerProvider).loadedModelId, testModel.id);
      expect(
        (c.read(llamaEngineProvider) as TestEngine).loadedWith?.backend,
        GpuBackend.cpu,
      );
    },
  );

  test(
    'Compare restores a chat model missing from the catalog via the DB',
    () async {
      ready();
      settings.useCpu();
      c.read(engineHandoffProvider.notifier).state = null;
      manager.chatLoaded();
      manager.omitCatalog();
      final resume = await manager.suspendChatForCompare();
      expect(c.read(modelManagerProvider).loadedModelId, isNull);
      expect(resume, isNotNull);
      await resume!();
      expect(c.read(modelManagerProvider).loadedModelId, testModel.id);
    },
  );

  test('Compare preserves a chat model with no restorable record', () async {
    manager.loaded();
    expect(await manager.suspendChatForCompare(), isNull);
    expect(c.read(modelManagerProvider).loadedModelId, 'manual');
    expect(loads, 0);
  });

  for (final action in [
    'restore',
    'eject',
    'pick',
    'remote',
    'busy',
    'loaded',
  ]) {
    test('Compare restoration: $action', () async {
      ready();
      settings.useCpu();
      manager.chatLoaded();
      final resume = await manager.suspendChatForCompare();
      expect(resume, isNotNull);
      expect(c.read(modelManagerProvider).loadedModelId, isNull);
      loads = 0;
      switch (action) {
        case 'eject':
          await manager.unloadModel();
        case 'pick':
          await expectLater(
            manager.loadModel(testModel.copyWith(isDownloaded: false)),
            throwsStateError,
          );
        case 'remote':
          settings.remote(true);
        case 'busy':
          c.read(sessionBusyProvider.notifier).state = true;
        case 'loaded':
          manager.loaded();
      }
      loads = 0;
      await resume!();
      // The normal loading pipeline reaches the injected VRAM handoff. It
      // fails on purpose, proving restoration still respects that guard.
      expect(loads, action == 'restore' ? 1 : 0);
    });
  }

  for (final action in [
    'remote',
    'remote round trip',
    'loaded',
    'loading',
    'busy',
    'generating',
    'manual load',
  ]) {
    test('$action during database read supersedes startup restore', () async {
      ready();
      db.readGate = Completer<void>();
      final restore = manager.restoreLastModel();
      await db.reading.future;
      switch (action) {
        case 'remote':
          settings.remote(true);
        case 'remote round trip':
          settings.remote(true);
          settings.remote(false);
        case 'loaded':
          manager.loaded();
        case 'loading':
          manager.loading();
        case 'busy':
          c.read(sessionBusyProvider.notifier).state = true;
        case 'generating':
          (c.read(chatProvider.notifier) as _Chat).generating();
        case 'manual load':
          await expectLater(
            manager.loadModel(testModel.copyWith(isDownloaded: false)),
            throwsStateError,
          );
      }
      db.readGate!.complete();
      await restore;
      expect(loads, 0);
      expect(c.read(islandProvider).activity, isNull);
      expect(await LastModelStore.read(), testModel.id);
    });
  }
  test(
    'foreground memory failure still reports error and offers Load anyway',
    () async {
      ready();
      await LastModelStore.forget();
      await expectLater(manager.loadModel(testModel), throwsA(anything));
      expect(c.read(modelManagerProvider).error, isNotNull);
      expect(c.read(islandProvider).toast?.action, isNotNull);
    },
  );
}
