import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/shared_providers.dart';
import '../../core/utils/priority_work_queue.dart';
import '../../data/network/web_search/search_models.dart';
import '../../data/storage/model_storage.dart';
import '../../inference/engine/llama_engine.dart';
import '../models/domain/entities/model_catalog.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import 'domain/evidence.dart';

/// Asks the optional source-check model whether a passage states an answer
/// sentence. It only clears sentences the word check could not place
/// ("uncertain", "not in the sources"); a conflict or a name the sources
/// lack is never overruled.
abstract class SupportJudge {
  /// The probability that each passage states its claim, in order. Stops
  /// early when [expired]: the list is then shorter than [pairs]. Null when
  /// the model is not available.
  Future<List<double>?> judge(
    List<({String claim, String passage})> pairs, {
    required bool Function() expired,
  });
}

class SupportCheck {
  /// P(yes) from which a sentence counts as stated by its passage.
  /// Conservative: an inconclusive judgement leaves the flag in place.
  static const supports = 0.8;

  /// The task line given to the reranker (Qwen3-Reranker is trained with
  /// task instructions; the default one ranks search results).
  static const instruction =
      'Judge whether the Document states the claim in the Query; answer yes only if the Document says it';

  /// Longest passage handed to the model, in characters.
  static const maxPassage = 700;

  /// yes/no logits to a probability; a single output is a logit of yes.
  static double probability(Map<String, double> scores) {
    final yes = scores['yes'] ?? scores.values.firstOrNull;
    if (yes == null) return 0;
    final no = scores['no'];
    final margin = no == null ? yes : yes - no;
    return 1 / (1 + math.exp(-margin));
  }

  static final _split = RegExp(r'(?<=[.!?])\s+|\n+');

  /// The [take] source passages (a sentence with its neighbours) that share
  /// most words with [claim], best first, at most one per source.
  static List<({int source, String passage})> windows(
    String claim,
    List<SearchResult> sources, {
    int take = 2,
  }) {
    final words = EvidenceRanker.terms(claim).toSet();
    if (words.isEmpty) return const [];
    final found = <({int source, String passage, double share})>[];
    for (var k = 0; k < sources.length; k++) {
      final s = sources[k];
      final text = '${s.title}\n${s.snippet}\n${s.pageText ?? ''}';
      final parts = [
        for (final p in text.split(_split))
          if (p.trim().isNotEmpty) p.trim(),
      ];
      var best = -1;
      var share = 0.0;
      for (var i = 0; i < parts.length; i++) {
        final v =
            words.intersection(EvidenceRanker.terms(parts[i]).toSet()).length /
            words.length;
        if (v > share) {
          share = v;
          best = i;
        }
      }
      if (best < 0) continue;
      var passage = [
        if (best > 0) parts[best - 1],
        parts[best],
        if (best + 1 < parts.length) parts[best + 1],
      ].join(' ');
      if (passage.length > maxPassage) {
        // Keep the best sentence whole when it fits.
        final start = best > 0 && parts[best].length <= maxPassage
            ? math.max(0, passage.indexOf(parts[best]) - 100)
            : 0;
        final end = math.min(passage.length, start + maxPassage);
        passage = passage.substring(start, end);
      }
      found.add((source: k, passage: passage, share: share));
    }
    found.sort((a, b) => b.share.compareTo(a.share));
    return [
      for (final f in found.take(take)) (source: f.source, passage: f.passage),
    ];
  }
}

/// [SupportJudge] with the reranker GGUF in its own runtime, loaded on
/// first use and released after two idle minutes.
class LlamaSupportJudge implements SupportJudge {
  final LlamaEngine engine;
  final Future<bool> Function() available;
  final _queue = PriorityWorkQueue();
  Timer? _idle;
  LlamaSupportJudge(this.engine, this.available);

  @override
  Future<List<double>?> judge(
    List<({String claim, String passage})> pairs, {
    required bool Function() expired,
  }) => _queue.submit(() async {
    if (pairs.isEmpty) return const <double>[];
    if (!engine.isLoaded) {
      if (!await available()) return null;
      final file = await ModelStorage.modelFile(supportCheckModel.fileName);
      await engine.loadEmbedder(modelPath: file.path, contextSize: 1024);
    }
    _idle?.cancel();
    try {
      final out = <double>[];
      // One pair per call, so the budget can stop between them.
      for (final p in pairs) {
        if (expired()) break;
        final scores = await engine.score([
          (query: p.claim, document: p.passage),
        ], instruction: SupportCheck.instruction);
        out.add(SupportCheck.probability(scores.first));
      }
      return out;
    } finally {
      _idle = Timer(const Duration(minutes: 2), () => unawaited(release()));
    }
  }, cancelled: expired);

  /// Frees the model's memory; the next call loads it again.
  Future<void> release() => _queue.submit(() async {
    _idle?.cancel();
    if (engine.isLoaded && !engine.isBusy) await engine.unload();
  }, priority: -1);

  void dispose() => _idle?.cancel();
}

final supportJudgeProvider = Provider<SupportJudge>((ref) {
  final judge = LlamaSupportJudge(
    ref.watch(supportEngineProvider),
    () async => ref.read(modelManagerProvider).supportCheckReady,
  );
  ref.onDispose(judge.dispose);
  return judge;
});
