// Photo turns and the prompt cache on a real vision model: the first turn
// encodes the photo, the follow-up must reuse it (and the conversation)
// instead of re-encoding everything. Prints VISION: JSON lines. Run through
// scripts/test-android.ps1 -Model <gguf> -Mmproj <mmproj.gguf>
// -Test integration_test/vision_cache_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:path_provider/path_provider.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _mmprojPath = String.fromEnvironment('MMPROJ');
const _backendName = String.fromEnvironment(
  'SMOKE_BACKEND',
  defaultValue: 'cpu',
);
const _threads = int.fromEnvironment('BENCH_THREADS', defaultValue: 6);

/// A 640×480 PNG: a red square on white, drawn here so the test needs no
/// asset. [seed] shifts the square so two files differ.
Future<String> _photo(Directory dir, String name, {int seed = 0}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 640, 480),
    Paint()..color = const Color(0xFFFFFFFF),
  );
  canvas.drawRect(
    Rect.fromLTWH(160.0 + seed * 40, 120, 240, 240),
    Paint()..color = const Color(0xFFD00000),
  );
  final image = await recorder.endRecording().toImage(640, 480);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('a follow-up in a photo chat reuses the encoded photo', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Vision cache test'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to the script.');
    expect(_mmprojPath, isNotEmpty, reason: 'Pass -Mmproj to the script.');
    expect(await File(_modelPath).exists(), true);
    expect(await File(_mmprojPath).exists(), true);
    final dir = await getApplicationCacheDirectory();
    final photo = await _photo(dir, 'vision-a.png');
    final other = await _photo(dir, 'vision-b.png', seed: 2);
    final engine = LlamaEngine(cacheDirectory: () async => dir.path);
    addTearDown(engine.dispose);
    final settings = InferenceSettings(
      backend: GpuBackend.values.byName(_backendName),
      contextSize: 4096,
      maxTokens: 48,
      temperature: 0,
      cpuThreads: _threads,
      batchThreads: _threads,
      thinkingModeEnabled: false,
    );
    await engine.loadModel(
      modelPath: _modelPath,
      mmprojPath: _mmprojPath,
      settings: settings,
    );
    expect(engine.metrics['supportsVision'], true);

    Future<({String text, int ms, Map<String, dynamic> metrics})> turn(
      List<Map<String, Object>> messages,
    ) async {
      final started = DateTime.now();
      final text = await engine
          .generate(
            messages: messages,
            fallbackTemplate: '',
            settings: settings,
          )
          .join();
      final ms = DateTime.now().difference(started).inMilliseconds;
      final m = Map<String, dynamic>.from(engine.metrics);
      // ignore: avoid_print
      print(
        'VISION: ${jsonEncode({'ms': ms, 'mediaTokens': m['mediaTokens'], 'cachedPromptTokens': m['cachedPromptTokens'], 'firstTokenMs': m['firstTokenMs'], 'text': text.length > 120 ? text.substring(0, 120) : text})}',
      );
      return (text: text, ms: ms, metrics: m);
    }

    final system = {
      'role': 'system',
      'content': 'You are a helpful assistant. Answer in one short sentence.',
    };
    final ask = {
      'role': 'user',
      'content': '${TextEngine.mediaMarker}\nWhat colour is the square?',
      'images': [photo],
    };
    final first = await turn([system, ask]);
    final mediaTokens = (first.metrics['mediaTokens'] as num).toInt();
    expect(mediaTokens, greaterThan(16));
    expect(first.metrics['cachedPromptTokens'], 0);
    expect(first.text.toLowerCase(), contains('red'));

    // Follow-up: the photo and the first exchange are already resident.
    final second = await turn([
      system,
      ask,
      {'role': 'assistant', 'content': first.text.trim()},
      {'role': 'user', 'content': 'And what shape is it?'},
    ]);
    final reused = (second.metrics['cachedPromptTokens'] as num).toInt();
    expect(
      reused,
      greaterThan(mediaTokens ~/ 2),
      reason: 'the follow-up should keep the encoded photo',
    );
    expect(
      second.metrics['firstTokenMs'],
      lessThan(first.metrics['firstTokenMs']),
      reason: 'no re-encode, no full re-prefill',
    );

    // A different photo in the same slot: the prefix ends before the image.
    final third = await turn([
      system,
      {
        'role': 'user',
        'content': '${TextEngine.mediaMarker}\nWhat colour is the square?',
        'images': [other],
      },
    ]);
    expect(
      (third.metrics['cachedPromptTokens'] as num).toInt(),
      lessThan(mediaTokens),
    );
    expect((third.metrics['mediaTokens'] as num).toInt(), greaterThan(16));

    // A text-only turn afterwards still works and reuses the system prompt.
    final fourth = await turn([
      system,
      {'role': 'user', 'content': 'Say hello in three words.'},
    ]);
    expect(fourth.text.trim(), isNotEmpty);
    expect(fourth.metrics['mediaTokens'], 0);
  });
}
