// The source-check model (Qwen3-Reranker 0.6B) on the phone: does it say
// "yes" when a passage states a sentence in other words, and "no" when the
// figure, the subject or the claim differs? Labelled pairs in EN/FR/ES,
// through the same SupportCheck instruction and probability the app uses.
// Prints SUPPORT: JSON lines (probability, ms per pair) and a summary with
// the accuracy at SupportCheck.supports.
// Run through scripts/test-android.ps1 -Model <qwen3-reranker-0.6b-q8_0.gguf>
// -Test integration_test/support_check_probe_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/features/retrieval/support_check.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _threads = int.fromEnvironment('BENCH_THREADS', defaultValue: 4);

const _eiffel =
    'The Eiffel Tower was completed in 1889 for the World\'s Fair in Paris. '
    'Designed by the company of Gustave Eiffel, it was the tallest '
    'man-made structure in the world until the Chrysler Building was '
    'finished in New York in 1930. It is 330 metres tall.';
const _nikon =
    'Nikon announced the Z30 on June 29, 2022. The mirrorless camera has a '
    '20.9-megapixel APS-C sensor and no viewfinder, and it records 4K video '
    'at up to 30 frames per second.';
const _fr =
    'Montréal compte environ 1,8 million d\'habitants selon le recensement '
    'de 2021. La ville est située sur une île du fleuve Saint-Laurent.';
const _es =
    'El río Amazonas tiene unos 6.400 kilómetros de longitud y desemboca en '
    'el océano Atlántico, en el norte de Brasil.';

/// (claim, passage, stated?)
const _pairs = <(String, String, bool)>[
  ('Nothing built by people was higher until 1930.', _eiffel, true),
  ('Work on it finished in 1889, in time for an exhibition.', _eiffel, true),
  ('It stands 330 metres high.', _eiffel, true),
  ('It stands 300 metres high.', _eiffel, false),
  ('It was finished in 1899.', _eiffel, false),
  ('It is the tallest structure in the world today.', _eiffel, false),
  ('The tower was repainted for the 1900 Olympic Games.', _eiffel, false),
  ('The Z30 was unveiled at the end of June 2022.', _nikon, true),
  ('It has no viewfinder.', _nikon, true),
  ('It has an electronic viewfinder.', _nikon, false),
  ('Its sensor is full frame.', _nikon, false),
  ('It films 4K at 60 frames per second.', _nikon, false),
  ('It costs 699 dollars.', _nikon, false),
  ('Environ 1,8 million de personnes vivent à Montréal.', _fr, true),
  ('Montréal a 3 millions d\'habitants.', _fr, false),
  ('Montréal se trouve sur une île.', _fr, true),
  ('El Amazonas mide alrededor de 6.400 km.', _es, true),
  ('El Amazonas desemboca en el océano Pacífico.', _es, false),
  ('The Amazon flows into the Atlantic Ocean.', _es, true),
  ('Paris is the capital of France.', _nikon, false),
];

void _report(String name, Map<String, Object?> data) =>
    debugPrint('SUPPORT: ${jsonEncode({'probe': name, ...data})}');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the source-check model tells stated from not stated', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Support probe'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to the script.');
    expect(await File(_modelPath).exists(), true);
    final engine = LlamaEngine();
    final clock = Stopwatch()..start();
    await engine.loadEmbedder(
      modelPath: _modelPath,
      threads: _threads,
      contextSize: 1024,
    );
    _report('load', {'ms': clock.elapsedMilliseconds});
    var right = 0;
    final ms = <int>[];
    final yes = <double>[], no = <double>[];
    for (final (claim, passage, stated) in _pairs) {
      clock.reset();
      final scores = await engine.score([
        (query: claim, document: passage),
      ], instruction: SupportCheck.instruction);
      final took = clock.elapsedMilliseconds;
      ms.add(took);
      final p = SupportCheck.probability(scores.first);
      (stated ? yes : no).add(p);
      final ok = (p >= SupportCheck.supports) == stated;
      if (ok) right++;
      _report('pair', {
        'claim': claim,
        'stated': stated,
        'p': double.parse(p.toStringAsFixed(3)),
        'ok': ok,
        'ms': took,
        'raw': scores.first,
      });
    }
    // The default task line, for comparison with the app's instruction.
    clock.reset();
    final plain = await engine.score([
      (query: _pairs[0].$1, document: _eiffel),
    ]);
    _report('default-instruction', {
      'p': SupportCheck.probability(plain.first),
      'ms': clock.elapsedMilliseconds,
    });
    ms.sort();
    double mean(List<double> v) =>
        v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
    _report('summary', {
      'pairs': _pairs.length,
      'right': right,
      'threshold': SupportCheck.supports,
      'meanStated': double.parse(mean(yes).toStringAsFixed(3)),
      'meanNotStated': double.parse(mean(no).toStringAsFixed(3)),
      // Not-stated pairs the app would clear: the costly mistake.
      'falseClears': no.where((p) => p >= SupportCheck.supports).length,
      'medianMs': ms[ms.length ~/ 2],
      'maxMs': ms.last,
    });
    await engine.unload();
    engine.dispose();
    expect(
      no.where((p) => p >= SupportCheck.supports),
      isEmpty,
      reason: 'a sentence the passage does not state must stay flagged',
    );
  });
}
