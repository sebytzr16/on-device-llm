// EmbeddingGemma 2 on the phone: text, photos and voice notes in one space.
// Each query must find its own item first (the Knowledge library and the
// web re-ranking rely on it), in English and across languages, at full
// size and cut to 256 dimensions. Prints EG2: JSON lines with timings.
// Run through scripts/test-android.ps1 -Model <embeddinggemma-2.gguf>
// -Mmproj <mmproj-embeddinggemma-2.gguf> -Test integration_test/eg2_probe_test.dart
// after copying test-assets/media/* into the .smoke app's files/media.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';

const _modelPath = String.fromEnvironment('BENCH_MODEL');
const _mmprojPath = String.fromEnvironment('MMPROJ');
const _threads = int.fromEnvironment('BENCH_THREADS', defaultValue: 6);

double _dot(Float32List a, Float32List b) {
  var s = 0.0;
  for (var i = 0; i < a.length && i < b.length; i++) {
    s += a[i] * b[i];
  }
  return s;
}

Float32List _cut(Float32List v, int dims) {
  final out = Float32List.fromList(v.sublist(0, dims));
  var n = 0.0;
  for (final x in out) {
    n += x * x;
  }
  final norm = n == 0 ? 1.0 : 1 / math.sqrt(n);
  for (var i = 0; i < out.length; i++) {
    out[i] *= norm;
  }
  return out;
}

/// For each query, the index of the best item, and the margin over the
/// runner-up.
List<(int, double)> _rank(List<Float32List> queries, List<Float32List> items) =>
    [
      for (final q in queries)
        () {
          final scores = [for (final i in items) _dot(q, i)];
          final order = List.generate(scores.length, (i) => i)
            ..sort((a, b) => scores[b].compareTo(scores[a]));
          return (order[0], scores[order[0]] - scores[order[1]]);
        }(),
    ];

void _report(String name, Map<String, Object?> data) =>
    debugPrint('EG2: ${jsonEncode({'probe': name, ...data})}');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('EmbeddingGemma 2 finds text, photos and voice notes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('EG2 probe'))),
    );
    expect(_modelPath, isNotEmpty, reason: 'Pass -Model to the script.');
    expect(await File(_modelPath).exists(), true);
    final q = embeddingModel.queryPrefix;
    final d = embeddingModel.documentPrefix;
    final engine = LlamaEngine();
    final clock = Stopwatch()..start();
    await engine.loadEmbedder(modelPath: _modelPath, threads: _threads);
    _report('load-text', {'ms': clock.elapsedMilliseconds});

    // ---- Text: documents and web passages --------------------------------
    const passages = [
      'The lease says rent of 1,450 dollars is due on the first day of each month, paid by bank transfer to the landlord.',
      'Dr. Martin\'s dental clinic confirmed a cleaning appointment on Thursday at 2:30 pm; arrive ten minutes early.',
      'The Nikon Z30 has a 20.9 megapixel APS-C sensor and records 4K video at up to 30 frames per second without a crop.',
      'Canberra was chosen as the capital of Australia in 1908 as a compromise between Sydney and Melbourne.',
      'To reset the router, hold the button on the back for ten seconds until the light blinks orange.',
      'The marathon training plan builds from 30 to 60 kilometres a week over twelve weeks, with one long run each Sunday.',
    ];
    const queries = [
      ('How much is my rent and when is it due?', 0),
      ('When is my dentist appointment?', 1),
      ('Nikon Z30 sensor resolution', 2),
      ('Why is Canberra the capital?', 3),
      ('how do I reset my wifi box', 4),
      ('Combien de kilomètres par semaine pour le marathon ?', 5),
      ('¿Cuándo es la cita con el dentista?', 1),
      ('Quel est le loyer ?', 0),
    ];
    clock.reset();
    final docs = <Float32List>[];
    for (final p in passages) {
      docs.addAll(await engine.embed(['$d$p']));
    }
    final docMs = clock.elapsedMilliseconds / passages.length;
    clock.reset();
    final qs = await engine.embed([for (final (t, _) in queries) '$q$t']);
    final queryMs = clock.elapsedMilliseconds / queries.length;
    var textHits = 0, textHits256 = 0;
    final ranked = _rank(qs, docs);
    final ranked256 = _rank(
      [for (final v in qs) _cut(v, 256)],
      [for (final v in docs) _cut(v, 256)],
    );
    // Exercise the production bridge's dimension parameter, rather than
    // only truncating 768-dimensional vectors inside the Dart probe.
    final nativeDocs256 = <Float32List>[];
    for (final p in passages) {
      nativeDocs256.addAll(await engine.embed(['$d$p'], dims: 256));
    }
    final nativeQs256 = await engine.embed([
      for (final (t, _) in queries) '$q$t',
    ], dims: 256);
    expect(nativeDocs256.every((v) => v.length == 256), isTrue);
    expect(nativeQs256.every((v) => v.length == 256), isTrue);
    final nativeRanks256 = _rank(nativeQs256, nativeDocs256);
    expect(
      nativeRanks256.map((r) => r.$1),
      orderedEquals(ranked256.map((r) => r.$1)),
    );
    for (var i = 0; i < queries.length; i++) {
      if (ranked[i].$1 == queries[i].$2) textHits++;
      if (ranked256[i].$1 == queries[i].$2) textHits256++;
      _report('text-query', {
        'query': queries[i].$1,
        'want': queries[i].$2,
        'got': ranked[i].$1,
        'margin': ranked[i].$2.toStringAsFixed(3),
        'got256': ranked256[i].$1,
      });
    }
    _report('text', {
      'hits': textHits,
      'hits256': textHits256,
      'nativeHits256': nativeRanks256.indexed
          .where((r) => r.$2.$1 == queries[r.$1].$2)
          .length,
      'of': queries.length,
      'msPerPassage': docMs.round(),
      'msPerQuery': queryMs.round(),
      'dims': docs.first.length,
    });
    await engine.unload();

    // ---- Photos and voice notes (projector) ---------------------------------
    if (_mmprojPath.isNotEmpty && await File(_mmprojPath).exists()) {
      final mediaDir = Directory('${File(_modelPath).parent.path}/media');
      final files = {
        'cat': '${mediaDir.path}/cat-384.jpg',
        'dog': '${mediaDir.path}/dog-384.jpg',
        'car': '${mediaDir.path}/car-384.jpg',
        'receipt': '${mediaDir.path}/receipt-384.jpg',
        'dentist': '${mediaDir.path}/memo-dentist.wav',
        'rent': '${mediaDir.path}/memo-rent.wav',
      };
      final present = {
        for (final e in files.entries)
          if (File(e.value).existsSync()) e.key: e.value,
      };
      _report('media-files', {'found': present.keys.toList()});
      clock.reset();
      await engine.loadEmbedder(
        modelPath: _modelPath,
        mmprojPath: _mmprojPath,
        threads: _threads,
      );
      _report('load-media', {'ms': clock.elapsedMilliseconds});
      final names = present.keys.toList();
      final vectors = <Float32List>[];
      for (final name in names) {
        clock.reset();
        vectors.addAll(
          await engine.embed([
            EmbedItem([present[name]!]),
          ]),
        );
        _report('media-item', {'item': name, 'ms': clock.elapsedMilliseconds});
      }
      const mediaQueries = {
        'cat': 'a photo of a cat',
        'dog': 'my dog',
        'car': 'picture of a car',
        'receipt': 'the shop receipt with the total',
        'dentist': 'voice note about the dentist appointment',
        'rent': 'reminder to pay the rent',
      };
      final asked = [
        for (final n in names)
          if (mediaQueries[n] != null) n,
      ];
      final mq = await engine.embed([
        for (final n in asked) '$q${mediaQueries[n]}',
      ]);
      // Among the photos and recordings alone, each query must pick its
      // own item. In a mixed library (the text passages too, two of which
      // say the same thing as the voice notes) it must be in the top 3.
      final mediaRanked = _rank(mq, vectors);
      final pool = [...vectors, ...docs];
      var mediaHits = 0, poolTop3 = 0;
      for (var i = 0; i < asked.length; i++) {
        final want = names.indexOf(asked[i]);
        if (mediaRanked[i].$1 == want) mediaHits++;
        final scores = [for (final v in pool) _dot(mq[i], v)];
        final order = List.generate(scores.length, (k) => k)
          ..sort((a, b) => scores[b].compareTo(scores[a]));
        final place = order.indexOf(want) + 1;
        if (place <= 3) poolTop3++;
        _report('media-query', {
          'query': mediaQueries[asked[i]],
          'want': asked[i],
          'got': names[mediaRanked[i].$1],
          'margin': mediaRanked[i].$2.toStringAsFixed(3),
          'placeInMixedLibrary': place,
        });
      }
      _report('media', {
        'hits': mediaHits,
        'top3InMixedLibrary': poolTop3,
        'of': asked.length,
      });
      await engine.unload();
      expect(
        mediaHits,
        greaterThanOrEqualTo(asked.length - 1),
        reason: 'photos and voice notes must be found by meaning',
      );
      expect(poolTop3, greaterThanOrEqualTo(asked.length - 1));
    }
    expect(
      textHits,
      greaterThanOrEqualTo(queries.length - 1),
      reason: 'text passages must be found by meaning',
    );
    expect(textHits256, greaterThanOrEqualTo(queries.length - 2));
  });
}
