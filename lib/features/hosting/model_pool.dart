import 'dart:async';
import 'dart:io';

import '../../inference/engine/llama_engine.dart';
import '../../inference/engine/text_engine.dart';
import '../models/domain/entities/model_info.dart';
import '../settings/domain/entities/inference_settings.dart';
import 'device_model_server.dart';

/// How the desktop server treats models other than the one it started with.
class PoolOptions {
  /// Load an installed model when a request names it.
  final bool jit;

  /// At most this many extra models stay loaded; the longest idle one makes
  /// room for the next.
  final int maxLoaded;

  /// Unload an extra model after it sat this long unused; null keeps it.
  final Duration? idleUnload;

  /// Models protected from automatic eviction and idle unload.
  final Set<String> pinned;

  /// Per-model idle limits; a present null value keeps the model loaded.
  final Map<String, Duration?> idleById;

  const PoolOptions({
    this.pinned = const {},
    this.idleById = const {},
    this.jit = false,
    this.maxLoaded = 2,
    this.idleUnload = const Duration(minutes: 10),
  });

  Map<String, Object?> toJson() => {
    'jit': jit,
    'maxLoaded': maxLoaded,
    'idleMinutes': idleUnload?.inMinutes,
    'pinned': pinned.toList(),
    'idleById': {
      for (final entry in idleById.entries)
        entry.key: entry.value?.inMicroseconds,
    },
  };

  factory PoolOptions.fromJson(Map<String, dynamic> j) => PoolOptions(
    pinned: (j['pinned'] as List?)?.whereType<String>().toSet() ?? const {},
    idleById: {
      for (final entry in (j['idleById'] as Map? ?? const {}).entries)
        if (entry.key is String)
          entry.key as String: entry.value == null
              ? null
              : Duration(microseconds: (entry.value as num).toInt()),
    },
    jit: j['jit'] == true,
    maxLoaded: ((j['maxLoaded'] as num?)?.toInt() ?? 2).clamp(1, 8),
    idleUnload: j.containsKey('idleMinutes')
        ? switch ((j['idleMinutes'] as num?)?.toInt()) {
            final m? when m > 0 => Duration(minutes: m),
            _ => null,
          }
        : const Duration(minutes: 10),
  );

  PoolOptions copyWith({
    Set<String>? pinned,
    Map<String, Duration?>? idleById,
    bool? jit,
    int? maxLoaded,
    Duration? idleUnload,
    bool keepLoaded = false,
  }) => PoolOptions(
    pinned: pinned ?? this.pinned,
    idleById: idleById ?? this.idleById,
    jit: jit ?? this.jit,
    maxLoaded: maxLoaded ?? this.maxLoaded,
    idleUnload: keepLoaded ? null : idleUnload ?? this.idleUnload,
  );
}

/// One extra model the server holds, for the server page's list.
class PooledModel {
  final String id;
  final bool loading, busy;
  final DateTime lastUsed;
  const PooledModel({
    required this.id,
    required this.loading,
    required this.busy,
    required this.lastUsed,
  });
}

class _Slot {
  final ModelInfo model;
  final LlamaEngine engine;
  Future<void>? loading;
  bool busy = false;
  DateTime lastUsed;
  _Slot(this.model, this.engine, this.lastUsed);
}

/// Desktop: the models the local server answers with besides its primary
/// one, each on its own runtime. A request for the chat's model while the
/// chat is idle is answered on the chat's runtime instead of a second copy.
class ModelPool implements ServedModelRouter {
  /// Installed models a request may name.
  final List<ModelInfo> Function() installed;
  final Future<void> Function(ModelInfo model, LlamaEngine engine) load;
  final InferenceSettings Function(ModelInfo model) settingsOf;
  final LlamaEngine Function() newEngine;
  final PoolOptions Function() options;

  /// The chat's runtime when it holds [id] (loaded, not loading).
  final LlamaEngine? Function(String id)? chatEngineFor;

  /// The primary model's id: never pooled, the server answers it itself.
  final String primary;
  final void Function()? onChange;
  final DateTime Function() now;

  final Map<String, _Slot> _slots = {};
  final Set<String> _onChat = {};
  Timer? _sweep;
  bool _closed = false;

  ModelPool({
    required this.installed,
    required this.load,
    required this.settingsOf,
    required this.newEngine,
    required this.options,
    required this.primary,
    this.chatEngineFor,
    this.onChange,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now {
    _sweep = Timer.periodic(const Duration(seconds: 30), (_) => sweep());
  }

  /// Whether a routed request is answering on the chat's runtime.
  bool get usingChat => _onChat.isNotEmpty;

  List<PooledModel> get loaded => [
    for (final s in _slots.values)
      PooledModel(
        id: s.model.id,
        loading: s.loading != null,
        busy: s.busy,
        lastUsed: s.lastUsed,
      ),
  ];

  ModelInfo? _model(String id) =>
      installed().where((m) => m.id == id && m.isDownloaded).firstOrNull;

  @override
  List<String> get ids {
    if (!options().jit) return _slots.keys.toList();
    return [
      for (final m in installed())
        if (m.isDownloaded && m.id != primary) m.id,
    ];
  }

  @override
  Future<TextEngine?> acquire(String id) async {
    if (_closed || id == primary) return null;
    final chat = _slots.containsKey(id) ? null : chatEngineFor?.call(id);
    if (chat != null) {
      // One copy is enough: wait for the chat rather than load another.
      if (chat.isBusy || _onChat.contains(id)) {
        throw RouteRefusal(
          HttpStatus.tooManyRequests,
          '$id is answering in the chat. Retry in a moment.',
        );
      }
      _onChat.add(id);
      return chat;
    }
    var slot = _slots[id];
    if (slot == null) {
      final model = _model(id);
      if (model == null || !options().jit) return null;
      // Requests loading other models at the same time may fill the room
      // again while this one waits.
      while (!_slots.containsKey(id) && _slots.length >= options().maxLoaded) {
        await _makeRoom();
        if (_closed) return null;
      }
      // Another request may have started loading it meanwhile.
      slot = _slots[id];
      if (slot == null) {
        final engine = newEngine();
        final created = slot = _Slot(model, engine, now());
        _slots[id] = created;
        created.loading = _load(created);
        onChange?.call();
      }
    }
    final loading = slot.loading;
    if (loading != null) await loading;
    if (_slots[id] != slot || _closed) {
      throw const RouteRefusal(
        HttpStatus.serviceUnavailable,
        'The model was unloaded. Retry.',
      );
    }
    if (slot.busy) {
      throw RouteRefusal(
        HttpStatus.tooManyRequests,
        '$id is answering another request.',
      );
    }
    slot
      ..busy = true
      ..lastUsed = now();
    onChange?.call();
    return slot.engine;
  }

  Future<void> _load(_Slot slot) async {
    try {
      await load(slot.model, slot.engine);
    } catch (e) {
      _slots.remove(slot.model.id);
      unawaited(_free(slot.engine));
      onChange?.call();
      throw RouteRefusal(
        HttpStatus.serviceUnavailable,
        '${slot.model.id} could not be loaded: ${_reason(e)}',
      );
    } finally {
      slot.loading = null;
    }
  }

  static String _reason(Object e) => switch (e) {
    StateError(:final message) => message,
    _ => '$e',
  };

  /// Unloads the longest idle models until one more fits.
  Future<void> _makeRoom() async {
    while (_slots.length >= options().maxLoaded) {
      final idle =
          _slots.values
              .where(
                (s) =>
                    !s.busy &&
                    s.loading == null &&
                    !options().pinned.contains(s.model.id),
              )
              .toList()
            ..sort((a, b) => a.lastUsed.compareTo(b.lastUsed));
      if (idle.isEmpty) {
        throw RouteRefusal(
          HttpStatus.tooManyRequests,
          _slots.keys.any(options().pinned.contains)
              ? 'Pinned or busy models fill the model pool. Unpin a model or retry when a request finishes.'
              : 'Every loaded model is busy. Retry in a moment.',
        );
      }
      await unload(idle.first.model.id);
    }
  }

  @override
  void release(String id) {
    if (_onChat.remove(id)) return;
    final slot = _slots[id];
    if (slot == null) return;
    slot
      ..busy = false
      ..lastUsed = now();
    onChange?.call();
  }

  @override
  InferenceSettings settingsFor(String id) {
    final model = _slots[id]?.model ?? _model(id);
    if (model == null) throw StateError('$id is not installed.');
    return settingsOf(model);
  }

  @override
  String templateFor(String id) =>
      (_slots[id]?.model ?? _model(id))?.family.fallbackTemplate ?? '';

  @override
  void cancelAll() {
    for (final s in _slots.values) {
      if (s.busy) s.engine.cancel();
    }
    for (final id in _onChat) {
      chatEngineFor?.call(id)?.cancel();
    }
  }

  /// Whether [id] is loaded here.
  bool holds(String id) => _slots.containsKey(id);

  /// Unloads idle models older than the idle limit.
  Future<void> sweep() async {
    for (final s in _slots.values.toList()) {
      final config = options();
      if (config.pinned.contains(s.model.id)) continue;
      final limit = config.idleById.containsKey(s.model.id)
          ? config.idleById[s.model.id]
          : config.idleUnload;
      if (limit == null) continue;
      final cutoff = now().subtract(limit);
      if (!s.busy && s.loading == null && s.lastUsed.isBefore(cutoff)) {
        await unload(s.model.id);
      }
    }
  }

  /// Frees [id]'s copy, waiting for its answer in progress to finish (at
  /// most [wait]).
  Future<void> unload(
    String id, {
    Duration wait = const Duration(minutes: 2),
  }) async {
    final slot = _slots[id];
    if (slot == null) return;
    final clock = Stopwatch()..start();
    while ((slot.busy || slot.loading != null) && clock.elapsed < wait) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (slot.busy) {
      throw StateError('$id is still answering a request.');
    }
    if (_slots[id] == slot) _slots.remove(id);
    onChange?.call();
    await _free(slot.engine);
  }

  static Future<void> _free(LlamaEngine engine) async {
    final clock = Stopwatch()..start();
    while (engine.isBusy && clock.elapsed < const Duration(seconds: 30)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    try {
      await engine.unload();
    } catch (_) {
      /* Disposing ends the worker anyway. */
    }
    engine.dispose();
  }

  /// Stops answering and frees every copy.
  Future<void> close() async {
    _closed = true;
    _sweep?.cancel();
    cancelAll();
    final slots = _slots.values.toList();
    _slots.clear();
    _onChat.clear();
    await Future.wait([
      for (final s in slots)
        () async {
          final clock = Stopwatch()..start();
          while (s.loading != null &&
              clock.elapsed < const Duration(minutes: 2)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await _free(s.engine);
        }(),
    ]);
  }
}
