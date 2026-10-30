import 'dart:math' as math;

import '../features/benchmark/benchmark.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../inference/engine/text_engine.dart';

/// Uses the existing benchmark metrics, with prompt caching disabled.
class ModelSpeedRun {
  final TextEngine engine;
  bool cancelled = false;
  bool _generating = false;
  ModelSpeedRun(this.engine);
  void cancel() {
    cancelled = true;
    if (_generating) engine.cancel();
  }

  Future<List<BenchmarkSample>> run({
    required InferenceSettings settings,
    required String template,
    required void Function(double) progress,
  }) async {
    final nativeContext =
        (engine.metrics['contextSize'] as num?)?.toInt() ??
        settings.contextSize;
    final limit = math.min(nativeContext, settings.contextSize);
    if (limit < 64) throw StateError('context');
    final reserve = math.min(128, limit ~/ 4);
    final fills = [
      512,
      4096,
      16384,
    ].map((n) => math.min(n, limit - reserve - 16)).toList();
    final config = settings.copyWith(
      maxTokens: reserve,
      temperature: 0,
      thinkingModeEnabled: false,
      promptCache: false,
    );
    final samples = <BenchmarkSample>[];
    for (var i = 0; i < fills.length; i++) {
      if (cancelled) return [];
      var words = math.max(1, fills[i] - 32);
      List<Map<String, Object>> messages() => [
        {
          'role': 'user',
          'content':
              'Read this passage and continue it. ${List.filled(words, ' hello').join()}',
        },
      ];
      var fits = false;
      for (var attempt = 0; attempt < 8; attempt++) {
        if (cancelled) return [];
        final preview = await engine.previewPrompt(
          messages: messages(),
          fallbackTemplate: template,
          settings: config,
        );
        final count = (preview['promptTokens'] as num?)?.toInt() ?? fills[i];
        fits = count + reserve < limit && preview['fits'] != false;
        if ((count - fills[i]).abs() <= 8 && fits) break;
        words = math.max(1, (words * fills[i] / math.max(1, count)).floor());
      }
      if (cancelled) return [];
      if (!fits) throw StateError('context');
      // Discard a warm-up at each fill before collecting its sample.
      for (var pass = 0; pass < 2; pass++) {
        if (cancelled) return [];
        _generating = true;
        try {
          await engine
              .generate(
                messages: messages(),
                fallbackTemplate: template,
                settings: config,
              )
              .drain<void>();
        } finally {
          _generating = false;
        }
        if (cancelled) return [];
        if (pass == 1) samples.add(BenchmarkSample.fromMetrics(engine.metrics));
        progress((i * 2 + pass + 1) / 6);
      }
    }
    return samples;
  }
}
