import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/prefs_rescue.dart';
import '../../../../data/network/hugging_face.dart';
import '../../../../data/storage/gguf_metadata.dart';
import '../../domain/entities/model_info.dart';
import '../../domain/model_recommendations.dart';

const _kKey = 'model_recommendations_v1';

/// What each model's makers recommend, as discovered from its file and,
/// next to a download, its Hugging Face repository. Keyed by model id; the
/// built-in table needs no storage and is merged in [forModel].
class ModelRecommendationsNotifier
    extends Notifier<Map<String, ModelRecommendation>> {
  SharedPreferences? _prefs;
  late Future<void> ready;
  bool _alive = true;
  Future<void> _writes = Future.value();
  final _checking = <String>{};

  @override
  Map<String, ModelRecommendation> build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_kKey);
      if (raw == null || !_alive) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      state = {
        for (final e in j.entries)
          e.key.toString(): ModelRecommendation.fromJson(e.value),
        ...state,
      };
    } catch (_) {
      await PrefsRescue.keepUnreadable(_prefs, _kKey);
    }
  }

  /// Reads the `general.sampling.*` keys of [m]'s file once. Local only.
  Future<void> learnFromFile(ModelInfo m, {bool force = false}) async {
    final path = m.localPath;
    if (path == null || !_checking.add(m.id)) return;
    try {
      await ready;
      if (!force && state[m.id]?.sources.contains('checked') == true) return;
      final meta = await GgufMetadata.inspect(path);
      final fromFile = ModelRecommendations.fromGguf(meta.sampling);
      final previous = state[m.id] ?? const ModelRecommendation();
      await _put(
        m.id,
        ModelRecommendation(
              values: previous.values,
              sources: [
                for (final s in previous.sources)
                  if (s != ModelRecommendations.sourceFile) s,
              ],
            )
            .merge(fromFile)
            .merge(const ModelRecommendation(sources: ['checked'])),
      );
    } catch (_) {
      // An unreadable header leaves the built-in values.
    } finally {
      _checking.remove(m.id);
    }
  }

  /// Looks up `generation_config.json` for a model downloaded from Hugging
  /// Face. Called next to the download only (the no-server rule allows
  /// Hugging Face for downloads), never on its own.
  Future<void> learnFromHub(ModelInfo m) async {
    final repo = ModelRecommendations.repoOf(m.downloadUrl);
    if (repo == null) return;
    final config = await HuggingFace.generationConfig(repo);
    if (config == null || !_alive) return;
    final hub = ModelRecommendations.fromGenerationConfig(config);
    if (hub.isEmpty) return;
    await ready;
    // The file's values, written from that same config at conversion,
    // stay on top.
    final previous = state[m.id] ?? const ModelRecommendation();
    await _put(m.id, hub.merge(previous));
  }

  Future<void> _put(String id, ModelRecommendation r) async {
    if (!_alive) return;
    state = {...state, id: r};
    final encoded = jsonEncode({
      for (final e in state.entries) e.key: e.value.toJson(),
    });
    _writes = _writes.then((_) async {
      try {
        _prefs ??= await SharedPreferences.getInstance();
        await _prefs!.setString(_kKey, encoded);
      } catch (_) {}
    });
    await _writes;
  }

  void forget(String id) {
    if (!state.containsKey(id)) return;
    unawaited(_put(id, const ModelRecommendation()));
  }
}

final modelRecommendationsProvider =
    NotifierProvider<
      ModelRecommendationsNotifier,
      Map<String, ModelRecommendation>
    >(ModelRecommendationsNotifier.new);

/// The recommendation for [m]: the built-in card table merged with what was
/// discovered. A file or `generation_config.json` holds one set of values;
/// for families whose card separates thinking and non-thinking sampling
/// (Qwen3, Qwen3.5) that set is usually the thinking one, so the card wins
/// there and the discovered values only fill keys it leaves open.
ModelRecommendation recommendationFor(
  ModelInfo m,
  Map<String, ModelRecommendation> discovered,
) {
  final card = ModelRecommendations.builtIn(m.fileName).isEmpty
      ? ModelRecommendations.builtIn(m.displayName)
      : ModelRecommendations.builtIn(m.fileName);
  final found = discovered[m.id] ?? const ModelRecommendation();
  final merged = card.thinking.isNotEmpty
      ? found.merge(card)
      : card.merge(found);
  return ModelRecommendation(
    values: merged.values,
    thinking: merged.thinking,
    sources: [
      for (final s in merged.sources)
        if (s != 'checked') s,
    ],
  );
}
