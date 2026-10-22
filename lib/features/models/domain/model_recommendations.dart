/// The sampling a model's makers recommend, applied as its own layer of the
/// settings cascade (request 2026-10-04: "fetch the default settings of
/// every model and apply them automatically; the user can still change
/// them"). Anything the user changes — globally, in the model's profile, a
/// preset or a chat — sits on top.
///
/// Three sources, later ones winning:
/// 1. a built-in table copied from the model cards ([builtIn]);
/// 2. `generation_config.json` of the model's Hugging Face repository, or of
///    the repository it was converted from, fetched next to a download;
/// 3. the `general.sampling.*` keys llama.cpp's converter writes into the
///    GGUF file from that same config (read from the file, no network).
///
/// Thinking models often recommend other values while they reason; those
/// are kept apart in [thinking] and applied when thinking is on.
class ModelRecommendation {
  final Map<String, dynamic> values;
  final Map<String, dynamic> thinking;

  /// Where the values came from, for the settings inspector
  /// ("model card", "Hugging Face", "model file").
  final List<String> sources;

  const ModelRecommendation({
    this.values = const {},
    this.thinking = const {},
    this.sources = const [],
  });

  bool get isEmpty => values.isEmpty && thinking.isEmpty;

  /// [other] on top of this one.
  ModelRecommendation merge(ModelRecommendation other) => ModelRecommendation(
    values: {...values, ...other.values},
    thinking: {...thinking, ...other.thinking},
    sources: [
      ...sources,
      for (final s in other.sources)
        if (!sources.contains(s)) s,
    ],
  );

  Map<String, dynamic> toJson() => {
    'values': values,
    if (thinking.isNotEmpty) 'thinking': thinking,
    'sources': sources,
  };

  static ModelRecommendation fromJson(Object? raw) {
    if (raw is! Map) return const ModelRecommendation();
    Map<String, dynamic> map(Object? v) =>
        v is Map ? Map<String, dynamic>.from(v) : const {};
    return ModelRecommendation(
      values: ModelRecommendations._clean(map(raw['values'])),
      thinking: ModelRecommendations._clean(map(raw['thinking'])),
      sources: [
        for (final s in (raw['sources'] as List?) ?? const [])
          if (s is String) s,
      ],
    );
  }
}

class ModelRecommendations {
  static const sourceCard = 'model card';
  static const sourceHub = 'Hugging Face';
  static const sourceFile = 'model file';

  /// The sampling keys a recommendation may set. Nothing else: a model's
  /// files must never change privacy, memory or hardware settings.
  static const keys = {
    'temperature',
    'topP',
    'topK',
    'minP',
    'typicalP',
    'repetitionPenalty',
    'presencePenalty',
    'frequencyPenalty',
    'repeatLastN',
  };

  static Map<String, dynamic> _clean(Map<String, dynamic> raw) {
    final out = <String, dynamic>{};
    for (final e in raw.entries) {
      if (!keys.contains(e.key)) continue;
      final v = e.value;
      if (v is! num || !v.isFinite) continue;
      out[e.key] = switch (e.key) {
        'topK' || 'repeatLastN' => v.toInt(),
        _ => v.toDouble(),
      };
    }
    // Out-of-range values would be rejected by the settings registry
    // anyway; drop them here so a bad file cannot reach the sampler.
    if ((out['temperature'] as double?)?.clamp(0, 2) != out['temperature']) {
      out.remove('temperature');
    }
    for (final k in ['topP', 'minP', 'typicalP']) {
      final v = out[k] as double?;
      if (v != null && (v < 0 || v > 1)) out.remove(k);
    }
    final topK = out['topK'] as int?;
    if (topK != null && (topK < 0 || topK > 200)) out['topK'] = 0;
    final rep = out['repetitionPenalty'] as double?;
    if (rep != null && (rep < 1 || rep > 2)) out.remove('repetitionPenalty');
    for (final k in ['presencePenalty', 'frequencyPenalty']) {
      final v = out[k] as double?;
      if (v != null && (v < -2 || v > 2)) out.remove(k);
    }
    return out;
  }

  /// `general.sampling.*` values from a GGUF header. llama.cpp writes -1 or
  /// 0 for "off" in top_k; both mean no top-k cut here (0).
  static ModelRecommendation fromGguf(Map<String, Object?> sampling) {
    double? d(String k) =>
        (sampling['general.sampling.$k'] as num?)?.toDouble();
    final topK = (sampling['general.sampling.top_k'] as num?)?.toInt();
    final values = _clean({
      'temperature': ?d('temp'),
      'topP': ?d('top_p'),
      'minP': ?d('min_p'),
      if (topK != null) 'topK': topK <= 0 ? 0 : topK,
      'repetitionPenalty': ?d('penalty_repeat'),
      'presencePenalty': ?d('penalty_present'),
      'frequencyPenalty': ?d('penalty_freq'),
      if (sampling['general.sampling.penalty_last_n'] is num)
        'repeatLastN': (sampling['general.sampling.penalty_last_n'] as num)
            .toInt(),
    });
    return values.isEmpty
        ? const ModelRecommendation()
        : ModelRecommendation(values: values, sources: const [sourceFile]);
  }

  /// A Hugging Face `generation_config.json`. Only meaningful when it asks
  /// for sampling (`do_sample` true or absent); greedy configs are ignored.
  static ModelRecommendation fromGenerationConfig(Map<String, dynamic> json) {
    if (json['do_sample'] == false) return const ModelRecommendation();
    final topK = (json['top_k'] as num?)?.toInt();
    final values = _clean({
      'temperature': ?json['temperature'],
      'topP': ?json['top_p'],
      'minP': ?json['min_p'],
      if (topK != null) 'topK': topK <= 0 ? 0 : topK,
      'typicalP': ?json['typical_p'],
      'repetitionPenalty': ?json['repetition_penalty'],
      'presencePenalty': ?json['presence_penalty'],
      'frequencyPenalty': ?json['frequency_penalty'],
    });
    return values.isEmpty
        ? const ModelRecommendation()
        : ModelRecommendation(values: values, sources: const [sourceHub]);
  }

  /// The Hugging Face repository a download link points at
  /// (`https://huggingface.co/<org>/<repo>/resolve/...`).
  static String? repoOf(String? downloadUrl) {
    if (downloadUrl == null) return null;
    final uri = Uri.tryParse(downloadUrl);
    if (uri == null || uri.host != 'huggingface.co') return null;
    final parts = uri.pathSegments;
    if (parts.length < 2) return null;
    return '${parts[0]}/${parts[1]}';
  }

  /// Values from the model cards, matched on the file or display name.
  /// Kept to families whose cards state their sampling.
  static ModelRecommendation builtIn(String name) {
    final n = name.toLowerCase().replaceAll(RegExp(r'[\s_]+'), '-');
    for (final entry in _cards) {
      if (entry.$1.hasMatch(n)) return entry.$2;
    }
    return const ModelRecommendation();
  }

  static final _cards = <(RegExp, ModelRecommendation)>[
    // Qwen3.5 / 3.6 card, "Best Practices": text without thinking
    // temperature 1.0, top_p 1.0, top_k 20, min_p 0, presence 2.0; with
    // thinking temperature 1.0, top_p 0.95, top_k 20, presence 1.5. The
    // 1.5 chosen for both (2026-10-04): 2.0 pushes a small model away
    // from repeating the names and figures an answer needs.
    (
      RegExp(r'qwen-?3\.[56]'),
      const ModelRecommendation(
        values: {
          'temperature': 1.0,
          'topP': 1.0,
          'topK': 20,
          'minP': 0.0,
          'presencePenalty': 1.5,
          'repetitionPenalty': 1.0,
        },
        thinking: {'topP': 0.95, 'presencePenalty': 1.5},
        sources: [sourceCard],
      ),
    ),
    // Qwen3 card: without thinking 0.7 / 0.8 / 20 / 0; with thinking
    // 0.6 / 0.95 / 20 / 0. Presence 1.5 is advised for quantized files.
    (
      RegExp(r'qwen-?3(?![.\d])'),
      const ModelRecommendation(
        values: {
          'temperature': 0.7,
          'topP': 0.8,
          'topK': 20,
          'minP': 0.0,
          'presencePenalty': 1.5,
          'repetitionPenalty': 1.0,
        },
        thinking: {'temperature': 0.6, 'topP': 0.95},
        sources: [sourceCard],
      ),
    ),
    // Gemma 3 and Gemma 4 cards: temperature 1.0, top_k 64, top_p 0.95,
    // min_p 0.
    (
      RegExp(r'gemma-?[34]'),
      const ModelRecommendation(
        values: {
          'temperature': 1.0,
          'topK': 64,
          'topP': 0.95,
          'minP': 0.0,
          'repetitionPenalty': 1.0,
        },
        sources: [sourceCard],
      ),
    ),
    // Llama 3.x generation_config: temperature 0.6, top_p 0.9.
    (
      RegExp(r'llama-?3'),
      const ModelRecommendation(
        values: {'temperature': 0.6, 'topP': 0.9, 'repetitionPenalty': 1.0},
        sources: [sourceCard],
      ),
    ),
    // SmolLM2 card: temperature 0.2, top_p 0.9.
    (
      RegExp(r'smollm'),
      const ModelRecommendation(
        values: {'temperature': 0.2, 'topP': 0.9, 'repetitionPenalty': 1.0},
        sources: [sourceCard],
      ),
    ),
  ];
}
