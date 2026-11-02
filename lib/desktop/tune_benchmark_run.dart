import 'dart:convert';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../features/models/domain/entities/model_info.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../inference/engine/text_engine.dart';
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
  bool cancelled = false;
  bool _generating = false;

  TuneBenchmarkRun({
    required this.engine,
    required this.model,
    required this.load,
    required this.estimate,
    required this.save,
    this.draftFile,
  });

  @override
  void cancel() {
    cancelled = true;
    if (_generating) engine.cancel();
  }

  static bool estimateFits(Map<String, dynamic> e, InferenceSettings s) {
    final ram = e['ramNeedMb'] as num?, available = e['ramAvailableMb'] as num?;
    if (ram == null ||
        available == null ||
        ram >
            ((e['ramBudgetMb'] as num?) ??
                available -
                    math.max(
                      1024,
                      ((e['ramTotalMb'] as num?) ?? available) / 8,
                    ))) {
      return false;
    }
    final gpu = (e['gpuLayers'] as num?) ?? 0;
    if (gpu <= 0) return true;
    final need = e['vramNeedMb'] as num?, free = e['vramFreeMb'] as num?;
    return need != null && free != null && need + s.vramReserveMb <= free;
  }

  @override
  Future<bool> fits(TuneSettings settings) async {
    if (cancelled) return false;
    final s = InferenceSettings.fromJson(settings);
    return estimateFits(await estimate(s), s);
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
    await load(s);
    if (cancelled) return const TuneMeasurement(0, '');
    final limit = math.min(
      s.contextSize,
      (engine.metrics['contextSize'] as num?)?.toInt() ?? s.contextSize,
    );
    if (limit < 256) throw StateError('context');
    // Quick (Optimize, one run per setup): a 1K-token long prompt and one
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
        rates = <double>[];
    Map<String, dynamic> effective = {};
    final steps = prompts.length * repetitions + (quick ? 1 : prompts.length);
    var done = 0;
    for (final entry in prompts.entries) {
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
        final output = await _generate(s, prompt);
        if (cancelled) return const TuneMeasurement(0, '');
        final m = engine.metrics;
        final rate = (m['tokensPerSecond'] as num?)?.toDouble() ?? 0;
        if (!rate.isFinite || rate <= 0 || output.isEmpty) {
          throw StateError('measurement');
        }
        final ttft = (m['firstTokenMs'] as num?)?.toDouble() ?? 0;
        // The bridge's own prompt-reading time (no prompt cache here, so
        // every prompt token is read); the first-token time otherwise.
        final prefillMs = (m['prefillMs'] as num?)?.toDouble() ?? 0;
        final reading = prefillMs > 0 ? prefillMs : ttft;
        final hash = benchmarkOutputHash(output);
        outputs.add(hash);
        rates.add(rate);
        effective = Map<String, dynamic>.from(
          (m['effective'] as Map?) ?? (m['effectiveSettings'] as Map?) ?? {},
        );
        rounds.add({
          'tokensPerSecond': rate,
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
      relativeNoise: noise,
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
