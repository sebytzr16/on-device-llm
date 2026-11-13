import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:ondevice_llm/features/voice/voice_models_provider.dart';
import 'package:ondevice_llm/features/voice/voice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'official Supertonic 3 archive is pinned and independently selectable',
    () {
      const pack = VoiceModels.supertonic;
      expect(VoiceModels.all, contains(pack));
      expect(VoiceModels.packs, isNot(contains(pack)));
      expect(pack.downloadKey, 'voice:supertonic-3');
      expect(pack.sizeBytes, 128774318);
      expect(
        pack.files.single.url,
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2',
      );
      expect(
        pack.files.single.sha256,
        '82fa96f91c4ef8abaae3a14a3f4153facf88bed821d1f7331cec2700f432c427',
      );
      expect(pack.unpackTo, 'sherpa-onnx-supertonic-3-tts-int8-2026-05-11');
      expect(VoiceModels.packsFor('supertonic-3'), [
        VoiceModels.listening,
        pack,
      ]);
      // The saved Supertonic 2 preference still selects Supertonic.
      expect(VoiceModels.packsFor('supertonic-2'), [
        VoiceModels.listening,
        pack,
      ]);
      expect(VoiceModels.packsFor('unknown'), VoiceModels.packs);
      expect(VoiceModels.isSupertonic('supertonic-2'), isTrue);
      expect(VoiceModels.isSupertonic('kokoro'), isFalse);
    },
  );

  test('Supertonic 3 languages are those it reads; others fall back', () {
    expect(VoiceModels.supertonicLanguages, hasLength(31));
    for (final lang in ['en', 'fr', 'es', 'de', 'ko', 'ja', 'vi', 'uk']) {
      expect(VoiceModels.supertonicLanguage(lang), lang, reason: lang);
    }
    expect(VoiceModels.supertonicLanguage('zh'), 'en');
    expect(VoiceModels.supertonicLanguage(''), 'en');
  });

  test('only Supertonic falls back to an older unpacked folder', () async {
    expect(await VoiceModels.isLegacyReady(VoiceModels.listening), isFalse);
    expect(await VoiceModels.isLegacyReady(VoiceModels.speaking), isFalse);
  });

  test('readiness belongs to the selected engine', () {
    const onlyKokoro = VoiceModelsState({
      'kokoro-v1.0': VoicePackState(VoicePackStatus.ready),
    });
    const onlySupertonic = VoiceModelsState({
      'supertonic-3': VoicePackState(VoicePackStatus.ready),
    });
    expect(onlyKokoro.canSpeakWith('supertonic-3'), isFalse);
    expect(onlyKokoro.canSpeakWith('kokoro'), isTrue);
    expect(onlySupertonic.canSpeakWith('supertonic-3'), isTrue);
    expect(onlySupertonic.canSpeakWith('supertonic-2'), isTrue);
    expect(onlySupertonic.canSpeak, isFalse);
  });

  for (final lang in ['en', 'fr', 'es']) {
    test('Supertonic sends $lang and the slider rate to sherpa', () {
      for (final engine in ['supertonic-2', 'supertonic-3']) {
        for (final speed in [0.6, 1.0, 1.3, 1.6]) {
          final config = speakingGenerationConfig({
            'engine': engine,
            'lang': lang,
            'sid': 4,
            'speed': speed,
          });
          expect(config.speed, speed);
          expect(config.extra, {'lang': lang});
          expect(config.sid, 4);
          expect(config.numSteps, 5);
        }
      }
    });
  }

  test('generation keeps Kokoro settings and bounds the reading speed', () {
    final config = speakingGenerationConfig({
      'engine': 'kokoro',
      'lang': 'en-us',
      'sid': 3,
      'speed': 1.3,
    });
    expect(config.speed, 1.3);
    expect(config.sid, 3);
    expect(config.extra, isEmpty);
    for (final (speed, expected) in [(0, 0.6), (3, 1.6)]) {
      expect(
        speakingGenerationConfig({
          'engine': 'supertonic-2',
          'lang': 'fr',
          'sid': 0,
          'speed': speed,
        }).speed,
        expected,
      );
    }
  });

  test('worker config selects only the requested model family', () {
    final supertonic = speakingModelConfig({
      'engine': 'supertonic-2',
      'supertonicDir': 'pack',
      'threads': 4,
    });
    expect(supertonic.kokoro.model, isEmpty);
    final model = supertonic.supertonic;
    expect(
      model.durationPredictor,
      p.join('pack', 'duration_predictor.int8.onnx'),
    );
    expect(model.textEncoder, p.join('pack', 'text_encoder.int8.onnx'));
    expect(model.vectorEstimator, p.join('pack', 'vector_estimator.int8.onnx'));
    expect(model.vocoder, p.join('pack', 'vocoder.int8.onnx'));
    expect(model.ttsJson, p.join('pack', 'tts.json'));
    expect(model.unicodeIndexer, p.join('pack', 'unicode_indexer.bin'));
    expect(model.voiceStyle, p.join('pack', 'voice.bin'));
    final kokoro = speakingModelConfig({
      'engine': 'kokoro',
      'model': 'kokoro.onnx',
      'voices': 'voices.bin',
      'tokens': 'tokens.txt',
      'dataDir': 'espeak',
      'lexicon': 'us.txt',
      'lang': 'en-us',
      'threads': 4,
    });
    expect(kokoro.kokoro.model, 'kokoro.onnx');
    expect(kokoro.kokoro.lang, 'en-us');
    expect(kokoro.supertonic.textEncoder, isEmpty);
  });

  test('Supertonic archive keeps every runtime file and its licence', () async {
    final temp = await Directory.systemTemp.createTemp('supertonic_unpack');
    addTearDown(() => temp.delete(recursive: true));
    final archive = Archive();
    for (final name in [
      'duration_predictor.int8.onnx',
      'text_encoder.int8.onnx',
      'vector_estimator.int8.onnx',
      'vocoder.int8.onnx',
      'tts.json',
      'unicode_indexer.bin',
      'voice.bin',
      'LICENSE',
    ]) {
      archive.addFile(ArchiveFile.string('supertonic/$name', name));
    }
    final file = File(p.join(temp.path, 'pack.tar.bz2'));
    file.writeAsBytesSync(BZip2Encoder().encode(TarEncoder().encode(archive)));
    final out = p.join(temp.path, 'out');
    VoiceModels.unpackArchive(file.path, out);
    for (final entry in archive) {
      expect(
        File(p.join(out, p.posix.basename(entry.name))).readAsStringSync(),
        p.posix.basename(entry.name),
      );
    }
    expect(File(p.join(out, VoiceModels.readyMarker)).existsSync(), isTrue);
  });

  test(
    'engine, speaker and speed persist through a settings provider restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = ProviderContainer();
      final notifier = first.read(settingsProvider.notifier);
      await notifier.ready;
      await notifier.update(
        first
            .read(settingsProvider)
            .copyWith(
              readingVoice: 'supertonic-2',
              supertonicSid: 7,
              readingSpeed: 1.3,
              localeCode: 'fr',
            ),
      );
      first.dispose();
      final second = ProviderContainer();
      addTearDown(second.dispose);
      await second.read(settingsProvider.notifier).ready;
      final restored = second.read(settingsProvider);
      expect(restored.readingVoice, 'supertonic-3');
      expect(restored.supertonicSid, 7);
      expect(restored.readingSpeed, 1.3);
      final engine = second.read(sherpaVoiceProvider);
      expect(engine.readingVoice, 'supertonic-3');
      final voice = second.read(voiceProvider.notifier).kokoroVoice();
      expect(voice.lang, 'fr');
      expect(voice.sid, 7);
      await second
          .read(settingsProvider.notifier)
          .update(restored.copyWith(readingVoice: 'kokoro'));
      expect(engine.readingVoice, 'kokoro');
      expect(second.read(voiceProvider.notifier).kokoroVoice().sid, 30);
    },
  );
}
