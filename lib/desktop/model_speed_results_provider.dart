import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/benchmark/benchmark.dart';
import '../features/settings/domain/entities/inference_settings.dart';

String modelSpeedShape(InferenceSettings s) => jsonEncode([
  s.backend.name,
  s.nGpuLayers,
  s.contextSize,
  s.flashAttention,
  s.kvCacheType.name,
  s.effectiveVCacheType.name,
  s.cpuThreads,
  s.batchSize,
  s.microBatchSize,
  s.batchThreads,
  s.mtp,
  s.draftModelId,
  s.draftMaxTokens,
  s.draftGpuLayers,
  s.expertsUsed,
  s.projectorDevice,
]);

class ModelSpeedResult {
  final String modelId, shape;
  final DateTime timestamp;
  final List<BenchmarkSample> samples;
  const ModelSpeedResult({
    required this.modelId,
    required this.shape,
    required this.timestamp,
    required this.samples,
  });
  String get key => jsonEncode([modelId, shape]);
  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'shape': shape,
    'timestamp': timestamp.toIso8601String(),
    'samples': [for (final s in samples) s.toJson()],
  };
  factory ModelSpeedResult.fromJson(Map<String, dynamic> j) => ModelSpeedResult(
    modelId: j['modelId'] as String,
    shape: j['shape'] as String,
    timestamp: DateTime.parse(j['timestamp'] as String),
    samples: [
      for (final s in j['samples'] as List)
        BenchmarkSample.fromJson(Map<String, dynamic>.from(s as Map)),
    ],
  );
}

class ModelSpeedResults extends Notifier<Map<String, ModelSpeedResult>> {
  static const storageKey = 'desktop_speed_results_v1';
  late Future<void> ready;
  bool _alive = true;
  Future<void> _writes = Future.value();
  @override
  Map<String, ModelSpeedResult> build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      final results = <String, ModelSpeedResult>{};
      try {
        for (final j
            in jsonDecode(prefs.getString(storageKey) ?? '[]') as List) {
          final r = ModelSpeedResult.fromJson(
            Map<String, dynamic>.from(j as Map),
          );
          results[r.key] = r;
        }
      } catch (_) {
        /* Unreadable results can be measured again. */
      }
      if (_alive) state = Map.unmodifiable(results);
    });
    return const {};
  }

  Future<void> save(ModelSpeedResult result) async {
    await ready;
    if (!_alive) return;
    state = Map.unmodifiable({...state, result.key: result});
    final encoded = jsonEncode([for (final r in state.values) r.toJson()]);
    _writes = _writes.then((_) async {
      await (await SharedPreferences.getInstance()).setString(
        storageKey,
        encoded,
      );
    });
    await _writes;
  }
}

final modelSpeedResultsProvider =
    NotifierProvider<ModelSpeedResults, Map<String, ModelSpeedResult>>(
      ModelSpeedResults.new,
    );
