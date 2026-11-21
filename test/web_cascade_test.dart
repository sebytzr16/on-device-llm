import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/island/status_island.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_model_pins.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/presets/domain/preset.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/effective_settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_sampling_variants_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'advanced_pages_2_test.dart'
    show draftModel, TestModels, TestSettings, WebAutoSettings;
import 'chat_test.dart' show TestEngine;

class _Chat extends ChatNotifier {
  @override
  ChatState build() => const ChatState(chatId: 'chat');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('declining the load question keeps the model and stays local', () async {
    var prompts = 0;
    var allow = false;
    final engine = TestEngine();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        chatProvider.overrideWith(_Chat.new),
        llamaEngineProvider.overrideWithValue(engine),
        webResearchConfirmationProvider.overrideWithValue(() async {
          prompts++;
          return allow;
        }),
      ],
    );
    addTearDown(container.dispose);
    final profiles = container.read(modelProfilesProvider.notifier);
    await profiles.ready;
    await profiles.set(draftModel.id, {'webMode': 'auto'});
    final manager = container.read(modelManagerProvider.notifier);

    // The other model's profile turns web research on, so switching asks.
    // "Stay local" must load it anyway, with web research off, instead of
    // stopping the switch like the user's Stop button (review 2026-11-20
    // finding 1).
    await manager.loadModel(draftModel);
    expect(prompts, 1);
    expect(container.read(modelManagerProvider).loadedModelId, draftModel.id);
    expect(engine.loadedWith?.webMode, WebMode.off);

    // Accepting the question loads the profile as it is.
    allow = true;
    await manager.unloadModel();
    await manager.loadModel(draftModel);
    expect(prompts, 2);
    expect(engine.loadedWith?.webMode, WebMode.auto);
  });

  test('a load with the turn\'s own settings never asks', () async {
    var prompts = 0;
    final engine = TestEngine();
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        chatProvider.overrideWith(_Chat.new),
        llamaEngineProvider.overrideWithValue(engine),
        webResearchConfirmationProvider.overrideWithValue(() async {
          prompts++;
          return false;
        }),
      ],
    );
    addTearDown(container.dispose);
    final profiles = container.read(modelProfilesProvider.notifier);
    await profiles.ready;
    await profiles.set(draftModel.id, {'webMode': 'auto'});
    final manager = container.read(modelManagerProvider.notifier);

    // A send (battery saver, image edit, a Goal) passes the settings it
    // resolved: they are the user's choice for that turn, so no dialog may
    // interrupt it (review 2026-11-20 finding 3).
    await manager.loadModel(
      draftModel,
      settings: const InferenceSettings().copyWith(webMode: WebMode.auto),
    );
    expect(prompts, 0);
    expect(engine.loadedWith?.webMode, WebMode.auto);
    expect(container.read(modelManagerProvider).loadedModelId, draftModel.id);

    // A chat load the user did not ask for (a Goal step) stays quiet too.
    await manager.loadModel(draftModel, forChat: true);
    expect(prompts, 0);
  });

  test('a refused pin keeps the model and keeps web research local', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    var prompts = 0;
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
        chatProvider.overrideWith(_Chat.new),
        webResearchConfirmationProvider.overrideWithValue(() async {
          prompts++;
          return false;
        }),
      ],
    );
    addTearDown(container.dispose);
    final profiles = container.read(modelProfilesProvider.notifier);
    final pins = container.read(chatModelPinsProvider.notifier);
    await profiles.ready;
    await pins.ready;
    await profiles.set(draftModel.id, {'webMode': 'auto'});
    container.read(chatOverridesProvider.notifier).state = {'topK': 20};

    await pins.set('chat', draftModel.id);

    // The pin the user chose is kept; web research is taken off for this
    // chat and the user is told, instead of the pin disappearing silently
    // (review 2026-11-20 finding 20).
    expect(prompts, 1);
    expect(container.read(chatModelPinsProvider), {'chat': draftModel.id});
    expect(container.read(chatOverridesProvider), {
      'topK': 20,
      'webMode': 'off',
    });
    expect(
      container.read(islandProvider).toast?.text,
      'Pinned. Web research stays off for this chat.',
    );
  });

  test(
    'new chats ask before dropping Off and the previous model pin',
    () async {
      var allow = false;
      var prompts = 0;
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          chatProvider.overrideWith(_Chat.new),
          webResearchConfirmationProvider.overrideWithValue(() async {
            prompts++;
            return allow;
          }),
        ],
      );
      addTearDown(container.dispose);
      final profiles = container.read(modelProfilesProvider.notifier);
      final pins = container.read(chatModelPinsProvider.notifier);
      await profiles.ready;
      await pins.ready;
      await profiles.set('test', {'webMode': 'always'});
      await pins.set('chat', draftModel.id);
      final overrides = container.read(chatOverridesProvider.notifier);
      overrides.state = {'webMode': 'off', 'topK': 20};
      final chat = container.read(chatProvider.notifier);

      expect(await chat.newChat(), isTrue);
      expect(container.read(chatProvider).chatId, isNull);
      expect(overrides.state, {'webMode': 'off'});
      expect(prompts, 1);

      allow = true;
      await chat.newChat();
      expect(overrides.state, isEmpty);
      expect(
        container.read(effectiveSettingsProvider).effective.webMode,
        WebMode.always,
      );
      expect(prompts, 2);
    },
  );

  test(
    'a chat inherits the pinned model profile, not the loaded one',
    () async {
      SharedPreferences.setMockInitialValues({
        'chat_model_pins_v1': jsonEncode({'chat': 'draft'}),
      });
      final container = ProviderContainer(
        overrides: [
          settingsProvider.overrideWith(TestSettings.new),
          modelManagerProvider.overrideWith(TestModels.new),
          chatProvider.overrideWith(_Chat.new),
        ],
      );
      addTearDown(container.dispose);
      await container.read(chatModelPinsProvider.notifier).ready;
      await container.read(modelProfilesProvider.notifier).set('draft', {
        'webMode': 'auto',
      });
      container.read(chatOverridesProvider.notifier).state = {'webMode': 'off'};
      // The loaded model is "test"; the next message really uses the pinned
      // "draft", whose profile turns web research on. Clearing this chat's Off
      // reveals it, so the inherited view and the preview must both say Auto
      // (audit 2026-11-20 P1-4).
      expect(container.read(activeModelIdProvider), 'draft');
      expect(
        container.read(effectiveSettingsProvider).effective.webMode,
        WebMode.off,
      );
      expect(
        container.read(chatInheritedSettingsProvider).webMode,
        WebMode.auto,
      );
      expect(
        container
            .read(settingsPreviewProvider(const SettingsChange(chat: {})))
            .effective
            .webMode,
        WebMode.auto,
      );
    },
  );

  test('a preset preview sees its own typed Off over a global Auto', () async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(WebAutoSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    const local = Preset(
      id: 'local',
      name: 'Local',
      emoji: '🔒',
      systemPrompt: '',
      webMode: WebMode.off,
    );
    // The active preset is General, so the user's Auto is what the next
    // message uses; this draft preset keeps research local, and the preview
    // must apply its typed Off over the global Auto.
    expect(
      container.read(effectiveSettingsProvider).effective.webMode,
      WebMode.auto,
    );
    expect(
      container
          .read(settingsPreviewProvider(const SettingsChange(preset: local)))
          .effective
          .webMode,
      WebMode.off,
    );
    // An override of Auto is the Off → Auto step a picker must confirm, even
    // though the global value never changed (audit 2026-11-20 P1-4).
    final withOverride = local.copyWith(overrides: const {'webMode': 'auto'});
    expect(
      container
          .read(settingsPreviewProvider(SettingsChange(preset: withOverride)))
          .effective
          .webMode,
      WebMode.auto,
    );
  });

  test('a sampling variant never turns web research on', () async {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(TestSettings.new),
        modelManagerProvider.overrideWith(TestModels.new),
      ],
    );
    addTearDown(container.dispose);
    final profiles = container.read(modelProfilesProvider.notifier);
    final variants = container.read(modelSamplingVariantsProvider.notifier);
    await profiles.ready;
    await profiles.set('test', {'webMode': 'auto', 'temperature': 0.2});
    // Saved with the whole profile; a variant keeps sampling only, so the
    // Auto stored beside it is not re-applied later (review 2026-11-20
    // finding 40).
    await variants.save('test', 'Warm', values: profiles.of('test'));
    expect(
      variants.of('test').variants.single.values.containsKey('webMode'),
      isFalse,
    );
    await profiles.set('test', {'webMode': 'off', 'temperature': 0.8});
    await variants.activate('test', 'Warm');
    expect(profiles.of('test')['webMode'], 'off');
    expect(profiles.of('test')['temperature'], 0.2);
  });
}
