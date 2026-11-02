import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_models_provider.dart';
import 'package:ondevice_llm/features/voice/voice_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final InferenceSettings initial;
  @override
  InferenceSettings build() {
    ready = Future.value();
    return initial;
  }

  @override
  Future<void> update(InferenceSettings next) async {
    state = next;
  }
}

class _Models extends ModelManagerNotifier {
  @override
  ModelManagerState build() {
    ready = Future.value();
    return const ModelManagerState(catalog: []);
  }
}

class _Packs extends VoiceModelsNotifier {
  _Packs(this.ready);
  final Set<String> ready;
  final downloaded = <VoicePack>[];
  final removed = <VoicePack>[];

  @override
  Future<void> download(VoicePack pack) async {
    downloaded.add(pack);
    state = VoiceModelsState({
      ...state.packs,
      pack.id: const VoicePackState(VoicePackStatus.ready),
    });
  }

  @override
  Future<void> delete(VoicePack pack) async {
    removed.add(pack);
    state = VoiceModelsState({
      ...state.packs,
      pack.id: const VoicePackState(VoicePackStatus.missing),
    });
  }

  @override
  VoiceModelsState build() => VoiceModelsState({
    for (final p in VoiceModels.all)
      p.id: VoicePackState(
        ready.contains(p.id) ? VoicePackStatus.ready : VoicePackStatus.missing,
      ),
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required Set<String> ready,
    InferenceSettings settings = const InferenceSettings(),
  }) async {
    tester.view.physicalSize = const Size(412, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith(() => _Settings(settings)),
        modelManagerProvider.overrideWith(_Models.new),
        voiceModelsProvider.overrideWith(() => _Packs(ready)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: SingleChildScrollView(child: NaturalVoiceSettings()),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('Parakeet is offered as a download and chosen only when there', (
    tester,
  ) async {
    await pump(
      tester,
      ready: {VoiceModels.listening.id, VoiceModels.speaking.id},
    );
    expect(find.byKey(const Key('listening-model')), findsOneWidget);
    expect(find.byKey(const Key('parakeet-add')), findsOneWidget);
    expect(find.textContaining('640 MB'), findsOneWidget);
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const Key('listening-parakeet')),
    );
    expect(chip.onSelected, isNull, reason: 'not downloaded yet');
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('listening-whisper')))
          .selected,
      isTrue,
    );
  });

  testWidgets('a downloaded Parakeet can be picked', (tester) async {
    final container = await pump(
      tester,
      ready: {
        VoiceModels.listening.id,
        VoiceModels.speaking.id,
        VoiceModels.parakeet.id,
      },
    );
    expect(find.byKey(const Key('parakeet-remove')), findsOneWidget);
    await tester.tap(find.byKey(const Key('listening-parakeet')));
    await tester.pump();
    expect(
      container.read(settingsProvider).listeningModel,
      VoiceModels.parakeetSetting,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('listening-parakeet')))
          .selected,
      isTrue,
    );
  });

  testWidgets(
    'selecting missing Supertonic offers its download and preserves Kokoro',
    (tester) async {
      final container = await pump(
        tester,
        ready: {VoiceModels.listening.id, VoiceModels.speaking.id},
      );
      expect(
        tester
            .widget<ChoiceChip>(find.byKey(const Key('reading-kokoro')))
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('reading-supertonic-2')));
      await tester.pump();
      expect(container.read(settingsProvider).readingVoice, 'supertonic-2');
      expect(find.textContaining('Supertonic 2'), findsWidgets);
      expect(find.byKey(const Key('voice-add')), findsOneWidget);
      expect(find.byKey(const Key('kokoro-voice')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('voice-add')));
      await tester.tap(find.byKey(const Key('voice-add')));
      await tester.pump();
      final packs = container.read(voiceModelsProvider.notifier) as _Packs;
      expect(packs.downloaded, [VoiceModels.supertonic]);
      expect(
        container.read(voiceModelsProvider).canSpeakWith('kokoro'),
        isTrue,
      );
      expect(find.text('Voice 10'), findsOneWidget);
      await tester.ensureVisible(find.text('Voice 5'));
      await tester.tap(find.text('Voice 5'));
      await tester.pump();
      expect(container.read(settingsProvider).supertonicSid, 4);
      await tester.ensureVisible(find.byKey(const Key('voice-remove')));
      await tester.tap(find.byKey(const Key('voice-remove')));
      await tester.pump();
      expect(packs.removed, [VoiceModels.listening, VoiceModels.supertonic]);
      expect(
        container.read(voiceModelsProvider).canSpeakWith('kokoro'),
        isTrue,
      );
      expect(find.byKey(const Key('voice-add')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('reading-kokoro')));
      await tester.tap(find.byKey(const Key('reading-kokoro')));
      await tester.pump();
      expect(container.read(settingsProvider).readingVoice, 'kokoro');
      expect(find.text('Heart'), findsOneWidget);
    },
  );
}
