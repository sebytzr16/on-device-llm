import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/constants/app_constants.dart';
import '../../core/device/thermal.dart';
import '../../core/providers/shared_providers.dart';
import '../../inference/engine/text_engine.dart';
import '../knowledge/knowledge_store.dart';
import '../models/domain/entities/model_info.dart';
import '../models/presentation/providers/model_manager_provider.dart';
import '../settings/presentation/providers/settings_provider.dart';
import '../tools/domain/tool_spec.dart';
import '../tools/tool_runner.dart';
import '../chat/domain/turn_prompts.dart';

/// One measured generation of the fixed prompt.
class BenchmarkSample {
  final double prefillMs, decodeTps, peakRssMb;
  final int promptTokens, generated;
  const BenchmarkSample({
    required this.prefillMs,
    required this.decodeTps,
    required this.peakRssMb,
    required this.promptTokens,
    required this.generated,
  });

  static BenchmarkSample fromMetrics(Map<String, dynamic> m) {
    num n(String k) => m[k] is num ? m[k] as num : 0;
    return BenchmarkSample(
      prefillMs: n('firstTokenMs').toDouble(),
      decodeTps: n('tokensPerSecond').toDouble(),
      peakRssMb: n('peakRssMb').toDouble(),
      promptTokens: n('promptTokens').toInt(),
      generated: n('tokens').toInt(),
    );
  }

  /// Prompt tokens per second during prefill.
  double get prefillTps => prefillMs > 0 ? promptTokens * 1000 / prefillMs : 0;

  Map<String, dynamic> toJson() => {
    'prefillMs': prefillMs,
    'decodeTps': decodeTps,
    'peakRssMb': peakRssMb,
    'promptTokens': promptTokens,
    'generated': generated,
  };

  factory BenchmarkSample.fromJson(Map<String, dynamic> j) => BenchmarkSample(
    prefillMs: (j['prefillMs'] as num?)?.toDouble() ?? 0,
    decodeTps: (j['decodeTps'] as num?)?.toDouble() ?? 0,
    peakRssMb: (j['peakRssMb'] as num?)?.toDouble() ?? 0,
    promptTokens: (j['promptTokens'] as num?)?.toInt() ?? 0,
    generated: (j['generated'] as num?)?.toInt() ?? 0,
  );
}

/// Median of [values]; 0 when empty.
double median(Iterable<double> values) {
  final v = values.toList()..sort();
  if (v.isEmpty) return 0;
  final mid = v.length ~/ 2;
  return v.length.isOdd ? v[mid] : (v[mid - 1] + v[mid]) / 2;
}

/// One fixed-prompt run (FX-07): what this phone does with this model on
/// this backend. Comparable across models, backends and phones. Since B5 a
/// run is one discarded warm-up generation followed by [samples] measured
/// ones; [prefillMs] and [decodeTps] are their medians, taken separately, and
/// [engine] holds the native effective settings (threads, batch, KV types,
/// flash attention) the numbers were produced with. [thermalBefore] /
/// [thermalAfter] are the readable thermal zones around the run. [chat] and
/// [chatTools] are one generation each with what a chat's first message
/// sends (review #8: the fixed prompt is the best case): the app's
/// system prompt, then also the tool descriptions; null when not measured.
class BenchmarkResult {
  final String modelId, modelName, backend, library;
  final int threads, batchThreads, contextSize, promptTokens, generated;
  final double prefillMs, decodeTps, peakRssMb;
  final DateTime runAt;
  final List<BenchmarkSample> samples;
  final Map<String, dynamic> engine;
  final Map<String, double> thermalBefore, thermalAfter;
  final BenchmarkSample? chat, chatTools;
  const BenchmarkResult({
    required this.modelId,
    required this.modelName,
    required this.backend,
    required this.library,
    required this.threads,
    required this.batchThreads,
    required this.contextSize,
    required this.promptTokens,
    required this.generated,
    required this.prefillMs,
    required this.decodeTps,
    required this.peakRssMb,
    required this.runAt,
    this.samples = const [],
    this.engine = const {},
    this.thermalBefore = const {},
    this.thermalAfter = const {},
    this.chat,
    this.chatTools,
  });

  /// Warm-up generations before the measured ones; the first run pays for
  /// page-faulting the weights and, on GPU backends, kernel compilation.
  static const warmUps = 1;

  /// Measured generations per run; medians come from these.
  static const samplesPerRun = 3;

  /// Prompt tokens per second during prefill.
  double get prefillTps => prefillMs > 0 ? promptTokens * 1000 / prefillMs : 0;

  /// The native settings that matter for a comparison, one line.
  String get engineSummary {
    if (engine.isEmpty) return '';
    final kv = engine['kvCacheType'], v = engine['vCacheType'];
    final parts = <String>[
      if (engine['threads'] != null)
        'threads ${engine['threads']}/${engine['batchThreads'] ?? '-'}',
      if (engine['batchSize'] != null)
        'batch ${engine['batchSize']}/${engine['microBatchSize'] ?? '-'}',
      if (kv != null) 'kv $kv${v != null && v != kv ? '/$v' : ''}',
      if (engine['flashAttentionPolicy'] != null)
        'fa ${engine['flashAttentionPolicy']}',
      if (engine['requestedGpuLayers'] != null)
        'gpu layers ${engine['requestedGpuLayers']}',
    ];
    return parts.join(' · ');
  }

  /// `cpu-0-3-1 41.2 → 98.9°C`: the zone that ended hottest, before and
  /// after the run (on Snapdragon that is a per-core junction sensor, not
  /// the skin), or `` when nothing was readable.
  String get thermalSummary {
    final zones = thermalAfter.isNotEmpty ? thermalAfter : thermalBefore;
    if (zones.isEmpty) return '';
    final name = zones.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    final before = thermalBefore[name], after = thermalAfter[name];
    if (before != null && after != null) {
      return '$name ${before.toStringAsFixed(1)} → ${after.toStringAsFixed(1)}°C';
    }
    return '$name ${(before ?? after)!.toStringAsFixed(1)}°C';
  }

  /// Text card for the share sheet and the clipboard.
  String card({String? device}) {
    final b = StringBuffer('OnDevice LLM benchmark\n');
    b.writeln('Model: $modelName');
    if (device != null) b.writeln('Device: $device');
    b.writeln('Backend: $backend · $library');
    b.writeln(
      'Threads: $threads decode / $batchThreads prefill · context $contextSize',
    );
    if (engineSummary.isNotEmpty) b.writeln('Engine: $engineSummary');
    final n = samples.length;
    final basis = n > 1 ? ' (median of $n, first run discarded)' : '';
    b.writeln(
      'Prefill: $promptTokens tokens in ${(prefillMs / 1000).toStringAsFixed(2)} s (${prefillTps.toStringAsFixed(0)} tok/s)$basis',
    );
    b.writeln(
      'Decode: ${decodeTps.toStringAsFixed(1)} tok/s over $generated tokens$basis',
    );
    if (n > 1) {
      b.writeln(
        'Samples: ${samples.map((s) => '${s.prefillTps.toStringAsFixed(0)}/${s.decodeTps.toStringAsFixed(1)}').join(', ')} tok/s (prefill/decode)',
      );
    }
    if (chat != null) b.writeln('Chat: ${chatLine(chat!)}');
    if (chatTools != null) b.writeln('Chat + tools: ${chatLine(chatTools!)}');
    b.writeln('Peak RSS: ${peakRssMb.round()} MB');
    if (thermalSummary.isNotEmpty) {
      b.writeln('Thermal: $thermalSummary (zone that ended hottest)');
    }
    b.write(
      'Run: ${runAt.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}',
    );
    return b.toString();
  }

  /// `944 tok · first token 4.85 s · 27.6 tok/s`.
  static String chatLine(BenchmarkSample s) =>
      '${s.promptTokens} tok · first token ${(s.prefillMs / 1000).toStringAsFixed(2)} s · ${s.decodeTps.toStringAsFixed(1)} tok/s';

  Map<String, dynamic> toJson() => {
    'modelId': modelId,
    'modelName': modelName,
    'backend': backend,
    'library': library,
    'threads': threads,
    'batchThreads': batchThreads,
    'contextSize': contextSize,
    'promptTokens': promptTokens,
    'generated': generated,
    'prefillMs': prefillMs,
    'decodeTps': decodeTps,
    'peakRssMb': peakRssMb,
    'runAt': runAt.toIso8601String(),
    'samples': [for (final s in samples) s.toJson()],
    'engine': engine,
    'thermalBefore': thermalBefore,
    'thermalAfter': thermalAfter,
    if (chat != null) 'chat': chat!.toJson(),
    if (chatTools != null) 'chatTools': chatTools!.toJson(),
  };

  factory BenchmarkResult.fromJson(Map<String, dynamic> j) => BenchmarkResult(
    modelId: j['modelId'] as String,
    modelName: j['modelName'] as String? ?? '',
    backend: j['backend'] as String? ?? '',
    library: j['library'] as String? ?? '',
    threads: (j['threads'] as num?)?.toInt() ?? 0,
    batchThreads: (j['batchThreads'] as num?)?.toInt() ?? 0,
    contextSize: (j['contextSize'] as num?)?.toInt() ?? 0,
    promptTokens: (j['promptTokens'] as num?)?.toInt() ?? 0,
    generated: (j['generated'] as num?)?.toInt() ?? 0,
    prefillMs: (j['prefillMs'] as num?)?.toDouble() ?? 0,
    decodeTps: (j['decodeTps'] as num?)?.toDouble() ?? 0,
    peakRssMb: (j['peakRssMb'] as num?)?.toDouble() ?? 0,
    runAt: DateTime.tryParse(j['runAt'] as String? ?? '') ?? DateTime.now(),
    samples: [
      for (final s in (j['samples'] as List? ?? const []))
        if (s is Map) BenchmarkSample.fromJson(Map<String, dynamic>.from(s)),
    ],
    engine: j['engine'] is Map
        ? Map<String, dynamic>.from(j['engine'] as Map)
        : const {},
    thermalBefore: _zones(j['thermalBefore']),
    thermalAfter: _zones(j['thermalAfter']),
    chat: j['chat'] is Map
        ? BenchmarkSample.fromJson(Map<String, dynamic>.from(j['chat'] as Map))
        : null,
    chatTools: j['chatTools'] is Map
        ? BenchmarkSample.fromJson(
            Map<String, dynamic>.from(j['chatTools'] as Map),
          )
        : null,
  );

  static Map<String, double> _zones(Object? v) => v is Map
      ? {
          for (final e in v.entries)
            if (e.value is num) e.key.toString(): (e.value as num).toDouble(),
        }
      : const {};

  /// The engine's info after a single run, folded into a result.
  static BenchmarkResult fromMetrics(
    Map<String, dynamic> m, {
    required ModelInfo model,
    required int threads,
    required int batchThreads,
  }) => fromSamples(
    m,
    [BenchmarkSample.fromMetrics(m)],
    model: model,
    threads: threads,
    batchThreads: batchThreads,
  );

  /// Folds the measured [samples] (warm-up already dropped) and the engine
  /// info [m] of the last one into a result: prefill and decode medians are
  /// taken independently, RSS is the peak, the token counts come from the
  /// last sample.
  static BenchmarkResult fromSamples(
    Map<String, dynamic> m,
    List<BenchmarkSample> samples, {
    required ModelInfo model,
    required int threads,
    required int batchThreads,
    Map<String, double> thermalBefore = const {},
    Map<String, double> thermalAfter = const {},
    BenchmarkSample? chat,
    BenchmarkSample? chatTools,
  }) {
    num n(String k) => m[k] is num ? m[k] as num : 0;
    final backend = (m['backend'] as String? ?? '—');
    final last = samples.isEmpty
        ? BenchmarkSample.fromMetrics(m)
        : samples.last;
    return BenchmarkResult(
      modelId: model.id,
      modelName: model.displayName,
      backend: backend.startsWith('CPU (') ? 'CPU' : backend,
      library: (m['nativeLibrary'] as String? ?? '')
          .replaceFirst(RegExp(r'^lib'), '')
          .replaceFirst(RegExp(r'\.so$'), ''),
      threads: threads,
      batchThreads: batchThreads,
      contextSize: n('contextSize').toInt(),
      promptTokens: last.promptTokens,
      generated: last.generated,
      prefillMs: median(samples.map((s) => s.prefillMs)),
      decodeTps: median(samples.map((s) => s.decodeTps)),
      peakRssMb: samples.fold(0, (p, s) => s.peakRssMb > p ? s.peakRssMb : p),
      runAt: DateTime.now(),
      samples: samples,
      engine: m['effectiveSettings'] is Map
          ? Map<String, dynamic>.from(m['effectiveSettings'] as Map)
          : const {},
      thermalBefore: thermalBefore,
      thermalAfter: thermalAfter,
      chat: chat,
      chatTools: chatTools,
    );
  }
}

class BenchmarkState {
  final String? running, error;
  final Map<String, BenchmarkResult> results;
  const BenchmarkState({this.running, this.error, this.results = const {}});
  BenchmarkState copyWith({
    String? running,
    bool clearRunning = false,
    String? error,
    bool clearError = false,
    Map<String, BenchmarkResult>? results,
  }) => BenchmarkState(
    running: clearRunning ? null : running ?? this.running,
    error: clearError ? null : error ?? this.error,
    results: results ?? this.results,
  );
}

/// Runs the fixed prompt through the local engine and keeps the last
/// result per model.
class BenchmarkNotifier extends Notifier<BenchmarkState> {
  static const _key = 'benchmarks_v1';

  /// ~380 tokens of ordinary prose: long enough that prefill dominates the
  /// first-token time, short enough to run on any phone in seconds.
  static const prompt =
      'Read the following passage and then write a summary of it in exactly three sentences.\n\n'
      'The city council met on Tuesday evening to discuss the proposed changes to the downtown transit plan. '
      'Under the new proposal, two bus routes that currently overlap along Main Street would be merged into a single '
      'high-frequency line running every six minutes during peak hours and every twelve minutes otherwise. '
      'Supporters argued that the change would reduce operating costs by roughly eight percent while shortening '
      'average wait times for most riders, and that the savings could fund an extension of the northern route to the '
      'new hospital campus, which opens next spring. Opponents, including several small business owners along the '
      'western section of the street, said the merged line would skip three stops that serve an older population and '
      'a community centre, and asked for a shuttle to cover the gap. The transit director acknowledged the concern and '
      'promised a revised map within two weeks, together with ridership figures for each affected stop over the past '
      'three years. The council voted to defer the decision until that data is available, and scheduled a public '
      'hearing for the second week of next month. Residents can submit written comments through the city website '
      'until the day before the hearing, and the director said every comment would be summarised in the report to '
      'the council. Several members noted that a similar merger in the eastern district two years ago had gone '
      'smoothly after an initial period of complaints, while one member cautioned that the eastern district had a '
      'younger population and better sidewalks, so the comparison should be made carefully.';

  /// The chat rows' message: an ordinary request with nothing to look up.
  static const chatQuestion = 'Give me three tips for better sleep.';

  late Future<void> ready;
  bool _alive = true;

  @override
  BenchmarkState build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const BenchmarkState();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw == null || !_alive) return;
      final list = jsonDecode(raw) as List;
      state = state.copyWith(
        results: {
          for (final e in list)
            if (e is Map)
              (e['modelId'] as String): BenchmarkResult.fromJson(
                Map<String, dynamic>.from(e),
              ),
        },
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(
        _key,
        jsonEncode([for (final r in state.results.values) r.toJson()]),
      );
    } catch (_) {}
  }

  /// The result of [from] now belongs to [to] (the catalog adopted a model
  /// the user had added another way).
  Future<void> rename(String from, String to) async {
    final r = state.results[from];
    if (r == null || state.results.containsKey(to)) return;
    final moved = BenchmarkResult.fromJson({...r.toJson(), 'modelId': to});
    state = state.copyWith(
      results: {
        for (final e in state.results.entries)
          if (e.key != from) e.key: e.value,
        to: moved,
      },
    );
    await _save();
  }

  /// Loads [model] with the current settings (prompt cache off so the whole
  /// prompt is evaluated), runs one greedy 128-token completion as warm-up
  /// and then [BenchmarkResult.samplesPerRun] measured ones, then the chat
  /// rows.
  Future<BenchmarkResult?> run(ModelInfo model) async {
    if (state.running != null || ref.read(sessionBusyProvider)) {
      throw StateError('Wait for the current response or benchmark.');
    }
    await ready;
    state = state.copyWith(running: model.id, clearError: true);
    ref.read(sessionBusyProvider.notifier).state = true;
    try {
      final manager = ref.read(modelManagerProvider.notifier);
      await manager.ready;
      await manager.loadModel(model, forChat: true);
      final settings = ref
          .read(settingsProvider)
          .copyWith(
            maxTokens: 128,
            temperature: 0,
            thinkingModeEnabled: false,
            promptCache: false,
          );
      final TextEngine engine = ref.read(llamaEngineProvider);
      final fallbackTemplate = model.family.fallbackTemplate;
      final thermalBefore = ThermalState.read();
      final samples = <BenchmarkSample>[];
      const total = BenchmarkResult.warmUps + BenchmarkResult.samplesPerRun;
      for (var i = 0; i < total; i++) {
        await engine
            .generate(
              messages: const [
                {'role': 'user', 'content': prompt},
              ],
              fallbackTemplate: fallbackTemplate,
              settings: settings,
            )
            .drain<void>();
        if (i >= BenchmarkResult.warmUps) {
          samples.add(BenchmarkSample.fromMetrics(engine.metrics));
        }
      }
      final metrics = engine.metrics;
      final thermalAfter = ThermalState.read();
      // The chat rows: what a first message sends, with thinking still
      // off. Memory notes and presets vary by chat and are left out.
      final system =
          '${AppConstants.defaultSystemPrompt}\n${settings.systemPrompt}';
      Future<BenchmarkSample> chatRun(
        String system, [
        List<ToolSpec> tools = const [],
      ]) async {
        await engine
            .generate(
              messages: [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': chatQuestion},
              ],
              fallbackTemplate: fallbackTemplate,
              settings: settings,
              tools: tools,
            )
            .drain<void>();
        return BenchmarkSample.fromMetrics(engine.metrics);
      }

      final chat = await chatRun(system);
      BenchmarkSample? chatTools;
      final specs = settings.toolsEnabled
          ? ToolRunner(
              scraper: ref.read(duckDuckGoScraperProvider),
              reader: ref.read(webPageReaderProvider),
              knowledge: ref.read(knowledgeStoreProvider),
              settings: settings,
              newsDesk: ref.read(newsDeskProvider),
            ).specs()
          : const <ToolSpec>[];
      if (specs.isNotEmpty) {
        final native = engine.metrics['supportsTools'] == true;
        chatTools = await chatRun(
          system + TurnPrompts.toolSystemText(specs, native: native),
          native ? specs : const [],
        );
      }
      final result = BenchmarkResult.fromSamples(
        metrics,
        samples,
        model: model,
        threads: settings.effectiveThreads,
        batchThreads: settings.effectiveBatchThreads,
        thermalBefore: thermalBefore,
        thermalAfter: thermalAfter,
        chat: chat,
        chatTools: chatTools,
      );
      if (_alive) {
        state = state.copyWith(
          results: {...state.results, model.id: result},
          clearRunning: true,
        );
        await _save();
      }
      return result;
    } catch (e) {
      if (_alive) state = state.copyWith(error: '$e', clearRunning: true);
      return null;
    } finally {
      ref.read(sessionBusyProvider.notifier).state = false;
    }
  }
}

final benchmarkProvider = NotifierProvider<BenchmarkNotifier, BenchmarkState>(
  BenchmarkNotifier.new,
);
