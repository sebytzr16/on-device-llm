import 'dart:math' as math;

import '../../inference/engine/llama_engine.dart';
import 'device_model_server.dart';

/// Keeps embedding work on its own worker and loaded model.
class LocalServedVectorEngine extends ServedVectorEngine {
  final String? Function(String id) modelPath;
  final LlamaEngine _engine = LlamaEngine();
  bool _busy = false;

  final Map<String, String> Function()? availableModels;
  LocalServedVectorEngine(this.modelPath, {this.availableModels});

  @override
  Map<String, String> get models => availableModels?.call() ?? const {};

  // Null (an engine library without counting) keeps HTTP embedding closed.
  @override
  Future<({List<int> counts, int limit})?> tokenCounts(
    String model,
    List<String> input,
  ) => _run(model, () => _engine.embedTokenCounts(input));

  Future<T> _run<T>(String model, Future<T> Function() action) async {
    if (_busy) throw const RouteRefusal(429, 'The embedding model is busy.');
    final path = modelPath(model);
    if (path == null) throw const RouteRefusal(400, 'Unknown embedding model.');
    _busy = true;
    try {
      await _engine.loadEmbedder(modelPath: path);
      return await action();
    } finally {
      _busy = false;
    }
  }

  @override
  Future<List<List<double>>> embed(
    String model,
    List<String> input,
    int dims,
  ) => _run(
    model,
    () async => [
      for (final row in await _engine.embed(input, dims: dims)) row.toList(),
    ],
  );

  @override
  Future<List<double>> rerank(
    String model,
    String query,
    List<String> documents,
  ) => _run(model, () async {
    final rows = await _engine.score([
      for (final document in documents) (query: query, document: document),
    ]);
    return [
      for (final row in rows)
        if (row.containsKey('yes') && row.containsKey('no'))
          1 / (1 + math.exp(row['no']! - row['yes']!))
        else if (row.containsKey('yes'))
          row['yes']!
        else
          row.values.first,
    ];
  });

  @override
  void dispose() => _engine.dispose();
}
