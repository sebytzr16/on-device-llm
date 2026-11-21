import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../models/domain/entities/model_info.dart';
import '../settings/domain/entities/inference_settings.dart';
import '../../core/logging/quiet_failure.dart';
import '../../inference/engine/text_engine.dart';
import 'benchmark_receipt.dart';
import 'model_tuner.dart';

/// Engine adapter: fixed greedy prompts, no prompt cache, warm-up after reload.
class TuneBenchmarkRun implements TuneRunner {
  final TextEngine engine;
  final ModelInfo model;
  final Future<void> Function(InferenceSettings) load;
  final Future<Map<String, dynamic>> Function(InferenceSettings) estimate;
  final Future<void> Function(BenchmarkReceipt) save;
  final String? draftFile;

  /// One deadline for the whole run (screening and verification). A sample
  /// started after it throws [OptimizeBudgetExhausted] instead of loading.
  final DateTime? deadline;

  /// The run's clock; tests advance it to exercise the deadline.
  final DateTime Function() now;

  /// Stops a model load in progress (the manager's stop-load path), so a
  /// cancel does not wait for a multi-GB load to finish.
  final void Function()? stopLoad;
  bool cancelled = false;
  bool _generating = false;

  /// The settings of the last load this run made, if any: the controller
  /// puts the chat's own settings back when a measured setup is still loaded.
  InferenceSettings? loadedWith;

  TuneBenchmarkRun({
    required this.engine,
    required this.model,
    required this.load,
    required this.estimate,
    required this.save,
    this.draftFile,
    this.deadline,
    DateTime Function()? now,
    this.stopLoad,
  }) : now = now ?? DateTime.now;

  bool get outOfTime => deadline != null && !now().isBefore(deadline!);

  @override
  void cancel() {
    cancelled = true;
    stopLoad?.call();
    if (_generating) engine.cancel();
  }

  static bool estimateFits(Map<String, dynamic> e, InferenceSettings s) {
    final ram = e['ramNeedMb'] as num?, available = e['ramAvailableMb'] as num?;
    // Unknown memory is not a refusal: an estimate without numbers used to
    // mark every setup as over budget, so nothing was measured at all. The
    // load itself decides then, and a setup that really fails is skipped.
    if (ram != null && available != null) {
      final budget =
          (e['ramBudgetMb'] as num?) ??
          available -
              math.max(1024, ((e['ramTotalMb'] as num?) ?? available) / 8);
      if (ram > budget) return false;
    }
    final gpu = (e['gpuLayers'] as num?) ?? 0;
    if (gpu <= 0) return true;
    final need = e['vramNeedMb'] as num?, free = e['vramFreeMb'] as num?;
    // The bridge counts unified GPU memory in RAM and reports no separate
    // VRAM budget for it.
    if (need == null || free == null) return true;
    return need + s.vramReserveMb <= free;
  }

  @override
  Future<bool> fits(TuneSettings settings) async {
    if (cancelled) return false;
    final s = InferenceSettings.fromJson(settings);
    final Map<String, dynamic> estimate;
    try {
      estimate = await this.estimate(s);
    } catch (e, st) {
      // An estimate that cannot run is unknown, not a refusal: the load
      // decides, and a setup whose load fails is skipped by its error.
      quietFailure('tune_estimate', e, st);
      return true;
    }
    return estimateFits(estimate, s);
  }

  void _checkDeadline() {
    if (outOfTime) throw const OptimizeBudgetExhausted();
  }

  /// Whether the model this run last loaded already matches [other] at load
  /// time. The benchmark's sampling (greedy, 128 tokens, no prompt cache) is
  /// set per request and never sticks to the loaded runtime, so only a
  /// load-time setting of a measured setup can be left behind.
  bool sameLoadAs(InferenceSettings other) {
    final loaded = loadedWith?.toJson();
    if (loaded == null) return true;
    final wanted = other.toJson();
    return InferenceSettings.loadTimeKeys.every(
      (key) => loaded[key] == wanted[key],
    );
  }

  Future<String> _generate(InferenceSettings s, String prompt) async {
    if (cancelled) return '';
    _generating = true;
    try {
      return await engine
          .generate(
            messages: [
              {'role': 'user', 'content': prompt},
            ],
            fallbackTemplate: model.family.fallbackTemplate,
            settings: s,
          )
          .join();
    } finally {
      _generating = false;
    }
  }

  @override
  Future<TuneMeasurement> measure(TuneSettings settings) =>
      benchmark(settings, repetitions: 3);

  Future<TuneMeasurement> benchmark(
    TuneSettings settings, {
    int repetitions = 1,
    void Function(double)? progress,
    bool quick = false,
  }) async {
    final s = InferenceSettings.fromJson(settings).copyWith(
      temperature: 0,
      seed: 42,
      maxTokens: 128,
      promptCache: false,
      thinkingModeEnabled: false,
      responseFormat: ResponseFormat.text,
      grammar: '',
      jsonSchema: '',
    );
    if (cancelled) return const TuneMeasurement(0, '');
    // Checked before the load too: a deadline hit must not start another
    // multi-GB load.
    _checkDeadline();
    await load(s);
    loadedWith = s;
    if (cancelled) return const TuneMeasurement(0, '');
    _checkDeadline();
    final limit = math.min(
      s.contextSize,
      (engine.metrics['contextSize'] as num?)?.toInt() ?? s.contextSize,
    );
    if (limit < 256) throw StateError('context');
    // Quick Optimize samples: a 1K-token long prompt and one
    // warm-up per load. A 26B MoE with experts in RAM reads ~24 prompt
    // tokens/s, so 4K twice took six minutes a setup (2026-10-28).
    final prompts = {
      'short': 'Describe how a seed grows into a tree.',
      'longPrefill':
          'Summarize this passage: ${List.filled(math.min(quick ? 1024 : 4096, limit - 192), 'hello ').join()}',
      'code':
          'Write a Python function that returns the first n Fibonacci numbers. Include a test.',
    };
    final classes = <String, dynamic>{},
        outputs = <String>[],
        texts = <String>[],
        rates = <double>[],
        latencies = <double>[];
    Map<String, dynamic> effective = {};
    final steps = prompts.length * repetitions + (quick ? 1 : prompts.length);
    var done = 0;
    for (final entry in prompts.entries) {
      _checkDeadline();
      var prompt = entry.value;
      var fits = false;
      for (var attempt = 0; attempt < 12 && !cancelled; attempt++) {
        final preview = await engine.previewPrompt(
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          fallbackTemplate: model.family.fallbackTemplate,
          settings: s,
        );
        final tokens = (preview['promptTokens'] as num?)?.toInt();
        fits =
            preview['fits'] != false &&
            tokens != null &&
            tokens + s.maxTokens < limit;
        if (fits) break;
        prompt = prompt.substring(0, math.max(1, prompt.length ~/ 2));
      }
      if (cancelled) return const TuneMeasurement(0, '');
      if (!fits) throw StateError('context');
      if (!quick || classes.isEmpty) {
        await _generate(s, prompt);
        progress?.call(++done / steps);
      }
      final rounds = <Map<String, dynamic>>[];
      for (var i = 0; i < repetitions && !cancelled; i++) {
        _checkDeadline();
        final elapsed = Stopwatch()..start();
        final output = await _generate(s, prompt);
        elapsed.stop();
        if (cancelled) return const TuneMeasurement(0, '');
        final m = engine.metrics;
        final rate = (m['tokensPerSecond'] as num?)?.toDouble() ?? 0;
        if (!rate.isFinite || rate <= 0 || output.isEmpty) {
          throw StateError('measurement');
        }
        final ttft = (m['firstTokenMs'] as num?)?.toDouble() ?? 0;
        // Native decode rate excludes the first token; add its full TTFT
        // (including begin/template work) for a measured end-to-end score.
        final first = (m['firstTokenFromBeginMs'] as num?)?.toDouble() ?? ttft;
        final tokens = (m['tokens'] as num?)?.toInt() ?? 0;
        latencies.add(
          first > 0 && tokens > 1
              ? first / 1000 + (tokens - 1) / rate
              : elapsed.elapsedMicroseconds / 1000000,
        );
        // The bridge's own prompt-reading time (no prompt cache here, so
        // every prompt token is read); the first-token time otherwise.
        final prefillMs = (m['prefillMs'] as num?)?.toDouble() ?? 0;
        final reading = prefillMs > 0 ? prefillMs : ttft;
        final hash = benchmarkOutputHash(output);
        outputs.add(hash);
        texts.add(output);
        rates.add(rate);
        effective = Map<String, dynamic>.from(
          (m['effective'] as Map?) ?? (m['effectiveSettings'] as Map?) ?? {},
        );
        rounds.add({
          'tokensPerSecond': rate,
          'elapsedSeconds': latencies.last,
          'firstTokenMs': ttft,
          'promptTokensPerSecond':
              m['promptTokensPerSecond'] ??
              (reading > 0
                  ? ((m['promptTokens'] as num?) ?? 0) * 1000 / reading
                  : 0),
          'draftAcceptance': m['draftAcceptRate'] ?? m['mtpAcceptRate'],
          'outputHash': hash,
          'promptTokens': m['promptTokens'],
          'generated': m['tokens'],
          'peakRssMb': m['peakRssMb'],
          'effective': effective,
        });
        progress?.call(++done / steps);
      }
      classes[entry.key] = {
        ...BenchmarkReceipt.statistics(rounds),
        'promptHash': benchmarkOutputHash(prompt),
      };
    }
    if (cancelled) return const TuneMeasurement(0, '');
    final receipt = BenchmarkReceipt({
      'schemaVersion': 1,
      'modelId': model.id,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'modelFile': p.basename(model.localPath ?? model.fileName),
      'sizeBytes': model.sizeBytes,
      'sha256': model.sha256,
      'quant': model.quantLabel,
      'nativeLibrary': engine.metrics['nativeLibrary'],
      'draftFile': draftFile == null ? null : p.basename(draftFile!),
      'backend': engine.metrics['backend'],
      'effective': effective,
      'requested': receiptSettings(settings),
      'generation': receiptSettings(s.toJson()),
      'promptClasses': classes,
      'outputHash': benchmarkOutputHash(jsonEncode(outputs)),
    });
    await save(receipt);
    var noise = 0.0;
    var stableOutput = true;
    for (final stats in classes.values) {
      noise = math.max(
        noise,
        (stats['spreadTokensPerSecond'] as num) /
            (stats['medianTokensPerSecond'] as num),
      );
      final rounds = stats['rounds'] as List;
      stableOutput =
          stableOutput &&
          rounds.map((r) => r['outputHash']).toSet().length == 1;
    }
    // Batch knobs are judged on the long prompt's reading speed.
    final long = classes['longPrefill'] as Map<String, dynamic>;
    final prefillRates = [
      for (final r in long['rounds'] as List)
        ((r as Map)['promptTokensPerSecond'] as num?)?.toDouble() ?? 0,
    ]..sort();
    final prefill = tuneMedian(prefillRates);
    return TuneMeasurement(
      math.exp(rates.map(math.log).reduce((a, b) => a + b) / rates.length),
      stableOutput ? receipt.json['outputHash'] as String : '',
      outputs: texts,
      relativeNoise: noise,
      workloadRate: latencies.every((s) => s > 0)
          ? repetitions / latencies.reduce((a, b) => a + b)
          : 0,
      prefillTokensPerSecond: prefill,
      prefillNoise: prefill > 0
          ? (prefillRates.last - prefillRates.first) / prefill
          : 0,
    );
  }

  static Map<String, dynamic> receiptSettings(Map<String, dynamic> settings) =>
      {
        for (final key in const [
          'contextSize',
          'imageMaxTokens',
          'backend',
          'nGpuLayers',
          'vramReserveMb',
          'flashAttention',
          'kvCacheType',
          'vCacheType',
          'cpuThreads',
          'batchThreads',
          'batchSize',
          'microBatchSize',
          'ropeScaling',
          'ropeFreqBase',
          'ropeFreqScale',
          'yarnExtFactor',
          'yarnAttnFactor',
          'yarnBetaFast',
          'yarnBetaSlow',
          'yarnOrigCtx',
          'mtp',
          'draftMaxTokens',
          'draftGpuLayers',
          'expertsUsed',
          'projectorDevice',
          'temperature',
          'seed',
          'maxTokens',
          'promptCache',
          'thinkingModeEnabled',
          'topP',
          'minP',
          'topK',
          'repetitionPenalty',
          'presencePenalty',
          'frequencyPenalty',
          'repeatLastN',
          'typicalP',
          'xtcProbability',
          'xtcThreshold',
          'topNSigma',
          'dryMultiplier',
          'dryBase',
          'dryAllowedLength',
          'dryPenaltyLastN',
          'samplerOrder',
          'stopSequences',
        ])
          if (settings.containsKey(key)) key: settings[key],
      };
}
