// Kokoro on each ONNX Runtime provider the phone's sherpa-onnx build offers
// (tester, 2026-10-07: "let Kokoro use the GPU"). Prints KOKORO: JSON lines
// with load and synthesis times; logcat shows whether a provider really
// ran or sherpa-onnx fell back to the CPU ("Fallback to cpu").
//
// Run through scripts/test-android.ps1 -Test
// integration_test/kokoro_provider_probe_test.dart -VoicePack
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/voice/sherpa_voice.dart';
import 'package:ondevice_llm/features/voice/voice_models.dart';
import 'package:path_provider/path_provider.dart';

void _report(Map<String, Object?> data) =>
    debugPrint('KOKORO: ${jsonEncode(data)}');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Kokoro speed per provider', (tester) async {
    final pack = Directory(
      '${(await getApplicationSupportDirectory()).path}/voice',
    );
    if (pack.existsSync()) {
      final models = await ModelStorage.modelsDir();
      for (final e in pack.listSync(recursive: true).whereType<File>()) {
        final to = File(
          '${models.path}/${e.path.substring(pack.path.length + 1)}',
        );
        if (to.existsSync() && to.lengthSync() == e.lengthSync()) continue;
        to.parent.createSync(recursive: true);
        e.copySync(to.path);
      }
    }
    final speaking = await VoiceModels.speakingPaths();
    expect(speaking, isNotNull, reason: 'copy the voice pack first');
    _report({
      'model': speaking!.model,
      'mb': File(speaking.model).lengthSync() ~/ 1048576,
    });
    const text =
        'Ottawa is the capital of Canada, and it sits on the Ottawa River, '
        'right across from Gatineau in the province of Quebec.';
    final en = KokoroVoice.forLanguage('en');
    for (final (provider, threads) in const [
      ('cpu', 2),
      ('cpu', 4),
      ('nnapi', 2),
      ('xnnpack', 2),
      ('qnn', 2),
      ('webgpu', 2),
    ]) {
      final clock = Stopwatch()..start();
      debugPrint('KOKORO-START $provider/$threads');
      try {
        final v = SherpaVoice(speakProvider: provider, speakThreads: threads);
        await v.warmSpeaking(en);
        final loadMs = clock.elapsedMilliseconds;
        final times = <int>[];
        var seconds = 0.0;
        for (var i = 0; i < 3; i++) {
          clock.reset();
          final audio = await v.synthesize(text, voice: en);
          times.add(clock.elapsedMilliseconds);
          seconds = audio!.pcm.length / audio.sampleRate;
        }
        v.dispose();
        _report({
          'provider': provider,
          'threads': threads,
          'loadMs': loadMs,
          'ms': times,
          'speechSeconds': seconds.toStringAsFixed(1),
        });
      } catch (e) {
        _report({'provider': provider, 'threads': threads, 'error': '$e'});
      }
    }
  });
}
