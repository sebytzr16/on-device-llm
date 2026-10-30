import 'dart:math' as math;

typedef TuneSettings = Map<String, dynamic>;

double tuneMedian(Iterable<double> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return 0;
  final i = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[i] : (sorted[i - 1] + sorted[i]) / 2;
}

class TuneMeasurement {
  final double tokensPerSecond;
  final String outputHash;
  final double relativeNoise;

  /// Prompt reading speed on a long prompt; 0 when not measured.
  final double prefillTokensPerSecond;
  final double prefillNoise;
  const TuneMeasurement(
    this.tokensPerSecond,
    this.outputHash, {
    this.relativeNoise = 0,
    this.prefillTokensPerSecond = 0,
    this.prefillNoise = 0,
  });
}

abstract class TuneRunner {
  Future<bool> fits(TuneSettings settings);
  Future<TuneMeasurement> measure(TuneSettings settings);
  void cancel();
}

enum TuneDecision { accepted, noise, changesOutput, memory, unsupported }

class TuneStep {
  final String knob;
  final Object? before, after;
  final double gain, noise;
  final TuneDecision decision;
  const TuneStep(
    this.knob,
    this.before,
    this.after,
    this.gain,
    this.noise,
    this.decision,
  );
}

enum TuneStatus { complete, drift, cancelled }

class TuneReport {
  final TuneStatus status;
  final List<TuneStep> steps;
  final TuneSettings changes;
  const TuneReport(this.status, this.steps, this.changes);
}

/// Reloads and warm-ups belong to the runner; decisions use measured rounds only.
class ModelTuner {
  final TuneRunner runner;
  bool _cancelled = false;
  ModelTuner(this.runner);

  void cancel() {
    _cancelled = true;
    runner.cancel();
  }

  /// Knobs that change how fast a prompt is read, not how fast tokens are
  /// written: judged on prefill speed (Jan's per-model logical/physical
  /// batch presets and llama.cpp's n_batch/n_ubatch, both permissive).
  static const prefillKnobs = {'batchSize', 'microBatchSize', 'batchThreads'};

  static double _rate(TuneMeasurement m, bool prefill) =>
      prefill ? m.prefillTokensPerSecond : m.tokensPerSecond;

  static double _spread(List<TuneMeasurement> samples, [bool prefill = false]) {
    final rates = samples.map((s) => _rate(s, prefill)).toList()..sort();
    final center = tuneMedian(rates);
    final spread = center > 0
        ? (rates.last - rates.first) / center
        : double.infinity;
    return math.max(
      spread,
      samples
          .map((s) => prefill ? s.prefillNoise : s.relativeNoise)
          .reduce(math.max),
    );
  }

  Future<TuneReport> run({
    required TuneSettings initial,
    required Map<String, List<Object>> candidates,
    Set<String> unsupported = const {},
    void Function(String)? progress,
  }) async {
    final current = TuneSettings.of(initial), changes = <String, dynamic>{};
    final steps = <TuneStep>[];
    TuneReport report(TuneStatus status) =>
        TuneReport(status, List.unmodifiable(steps), Map.unmodifiable(changes));

    Future<(List<TuneMeasurement>, List<TuneMeasurement>)> rounds(
      TuneSettings a,
      TuneSettings b,
    ) async {
      final left = <TuneMeasurement>[], right = <TuneMeasurement>[];
      for (var i = 0; i < 3 && !_cancelled; i++) {
        left.add(await runner.measure(Map.of(a)));
        if (_cancelled) break;
        right.add(await runner.measure(Map.of(b)));
      }
      return (left, right);
    }

    progress?.call('drift');
    final (aa, ab) = await rounds(current, current);
    if (_cancelled) return report(TuneStatus.cancelled);
    final aaMedian = tuneMedian(aa.map((s) => s.tokensPerSecond));
    final drift = aaMedian > 0
        ? (tuneMedian(ab.map((s) => s.tokensPerSecond)) / aaMedian - 1).abs()
        : double.infinity;
    final driftNoise = math.max(_spread(aa), _spread(ab));
    // Prefill is judged only when every drift round measured it.
    final prefillMeasured = [
      ...aa,
      ...ab,
    ].every((s) => s.prefillTokensPerSecond > 0);
    final prefillDriftNoise = prefillMeasured
        ? math.max(_spread(aa, true), _spread(ab, true))
        : 0.0;
    // A/B slots that read prompts at different speeds with the same
    // settings would turn that bias into a fake batch win.
    final aaPrefill = tuneMedian(aa.map((s) => s.prefillTokensPerSecond));
    final prefillDrift = prefillMeasured && aaPrefill > 0
        ? (tuneMedian(ab.map((s) => s.prefillTokensPerSecond)) / aaPrefill - 1)
              .abs()
        : 0.0;
    final prefillDrifts = prefillDrift > prefillDriftNoise;
    final hashes = {
      ...aa.map((s) => s.outputHash),
      ...ab.map((s) => s.outputHash),
    };
    if (!drift.isFinite ||
        drift > driftNoise ||
        hashes.length != 1 ||
        hashes.single.isEmpty) {
      return report(TuneStatus.drift);
    }
    for (final entry in candidates.entries) {
      for (final value in entry.value) {
        if (_cancelled) return report(TuneStatus.cancelled);
        final before = current[entry.key];
        if (before == value) continue;
        progress?.call(entry.key);
        final next = {...current, entry.key: value};
        if (unsupported.contains(entry.key)) {
          steps.add(
            TuneStep(entry.key, before, value, 0, 0, TuneDecision.unsupported),
          );
          break;
        }
        final fits = await runner.fits(next);
        if (_cancelled) return report(TuneStatus.cancelled);
        if (!fits) {
          steps.add(
            TuneStep(entry.key, before, value, 0, 0, TuneDecision.memory),
          );
          continue;
        }
        if (prefillDrifts && prefillKnobs.contains(entry.key)) {
          steps.add(
            TuneStep(
              entry.key,
              before,
              value,
              0,
              prefillDrift,
              TuneDecision.noise,
            ),
          );
          continue;
        }
        final (a, b) = await rounds(current, next);
        if (_cancelled) return report(TuneStatus.cancelled);
        final prefill =
            prefillMeasured &&
            prefillKnobs.contains(entry.key) &&
            [...a, ...b].every((s) => s.prefillTokensPerSecond > 0);
        final base = tuneMedian(a.map((s) => _rate(s, prefill)));
        final gain = base > 0
            ? tuneMedian(b.map((s) => _rate(s, prefill))) / base - 1
            : 0.0;
        final noise = math.max(
          prefill ? prefillDriftNoise : driftNoise,
          math.max(_spread(a, prefill), _spread(b, prefill)),
        );
        final sameOutput = [
          ...a,
          ...b,
        ].every((s) => s.outputHash == hashes.single);
        // Every paired candidate must win; a median alone can hide throttling.
        final stable = List.generate(
          3,
          (i) => _rate(b[i], prefill) > _rate(a[i], prefill) * (1 + noise),
        ).every((v) => v);
        final decision = !sameOutput
            ? TuneDecision.changesOutput
            : gain.isFinite && gain > noise && stable
            ? TuneDecision.accepted
            : TuneDecision.noise;
        steps.add(TuneStep(entry.key, before, value, gain, noise, decision));
        if (decision == TuneDecision.accepted) {
          current[entry.key] = value;
          changes[entry.key] = value;
        }
      }
    }
    return report(TuneStatus.complete);
  }
}
