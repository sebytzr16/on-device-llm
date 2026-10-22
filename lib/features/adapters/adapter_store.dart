import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/providers/shared_providers.dart';
import '../../data/storage/model_storage.dart';

/// A LoRA adapter GGUF the user imported (roadmap P2 "LoRA adapter
/// manifests"). The bridge validates the architecture against the base
/// model when it is attached; the manifest keeps what the header said.
class LoraAdapter {
  final String id;
  final String name;
  final String fileName;
  final String architecture;
  final double alpha;
  final String sha256;
  final int sizeBytes;
  final DateTime importedAt;
  const LoraAdapter({
    required this.id,
    required this.name,
    required this.fileName,
    required this.architecture,
    required this.alpha,
    required this.sha256,
    required this.sizeBytes,
    required this.importedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'fileName': fileName,
    'architecture': architecture,
    'alpha': alpha,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'importedAt': importedAt.toIso8601String(),
  };

  static LoraAdapter? fromJson(Map<String, dynamic> j) {
    final id = j['id'], fileName = j['fileName'];
    if (id is! String || fileName is! String) return null;
    return LoraAdapter(
      id: id,
      name: (j['name'] as String?) ?? id,
      fileName: fileName,
      architecture: (j['architecture'] as String?) ?? '',
      alpha: (j['alpha'] as num?)?.toDouble() ?? 0,
      sha256: (j['sha256'] as String?) ?? '',
      sizeBytes: (j['sizeBytes'] as num?)?.toInt() ?? 0,
      importedAt:
          DateTime.tryParse(j['importedAt']?.toString() ?? '') ??
          DateTime(1970),
    );
  }

  String get sizeLabel => sizeBytes >= 1 << 30
      ? '${(sizeBytes / (1 << 30)).toStringAsFixed(2)} GB'
      : '${(sizeBytes / (1 << 20)).toStringAsFixed(0)} MB';
}

/// An adapter applied to one model with a scale (1.0 = as trained).
class AdapterAttachment {
  final String adapterId;
  final double scale;
  const AdapterAttachment(this.adapterId, this.scale);
  Map<String, dynamic> toJson() => {'adapterId': adapterId, 'scale': scale};
}

class AdaptersState {
  final List<LoraAdapter> adapters;

  /// Model id → adapters applied when that model loads.
  final Map<String, List<AdapterAttachment>> attachments;
  final bool importing;
  final String? error;
  const AdaptersState({
    this.adapters = const [],
    this.attachments = const {},
    this.importing = false,
    this.error,
  });

  AdaptersState copyWith({
    List<LoraAdapter>? adapters,
    Map<String, List<AdapterAttachment>>? attachments,
    bool? importing,
    String? error,
    bool clearError = false,
  }) => AdaptersState(
    adapters: adapters ?? this.adapters,
    attachments: attachments ?? this.attachments,
    importing: importing ?? this.importing,
    error: clearError ? null : error ?? this.error,
  );

  List<AdapterAttachment> of(String modelId) =>
      attachments[modelId] ?? const [];

  LoraAdapter? byId(String id) => adapters.where((a) => a.id == id).firstOrNull;
}

/// Manifest `models/adapters.json`: imported adapter files plus which
/// models they are attached to. Files live beside the model weights so the
/// storage screen accounts for them.
class AdaptersNotifier extends Notifier<AdaptersState> {
  static const manifestName = 'adapters.json';
  late Future<void> ready;
  bool _alive = true;
  Future<void> _writes = Future.value();

  @override
  AdaptersState build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const AdaptersState();
  }

  Future<File> _manifest() async =>
      File(p.join((await ModelStorage.modelsDir()).path, manifestName));

  Future<void> _load() async {
    try {
      final f = await _manifest();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is! Map || !_alive) return;
      final adapters = <LoraAdapter>[];
      for (final e in (j['adapters'] as List?) ?? const []) {
        if (e is! Map) continue;
        final a = LoraAdapter.fromJson(Map<String, dynamic>.from(e));
        // A file that vanished (cleared storage) is dropped from the list.
        if (a != null && await ModelStorage.exists(a.fileName)) {
          adapters.add(a);
        }
      }
      final attachments = <String, List<AdapterAttachment>>{};
      final att = j['attachments'];
      if (att is Map) {
        for (final e in att.entries) {
          final list = <AdapterAttachment>[];
          for (final x in (e.value as List?) ?? const []) {
            if (x is! Map) continue;
            final id = x['adapterId'];
            if (id is! String || !adapters.any((a) => a.id == id)) continue;
            list.add(
              AdapterAttachment(
                id,
                ((x['scale'] as num?)?.toDouble() ?? 1).clamp(-2, 2),
              ),
            );
          }
          if (list.isNotEmpty) attachments[e.key.toString()] = list;
        }
      }
      if (_alive) {
        state = state.copyWith(adapters: adapters, attachments: attachments);
      }
    } catch (e) {
      if (_alive) state = state.copyWith(error: 'Adapter list unreadable: $e');
    }
  }

  Future<void> _save() async {
    final encoded = jsonEncode({
      'v': 1,
      'adapters': [for (final a in state.adapters) a.toJson()],
      'attachments': {
        for (final e in state.attachments.entries)
          e.key: [for (final a in e.value) a.toJson()],
      },
    });
    _writes = _writes.then((_) async {
      try {
        final f = await _manifest();
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(encoded, flush: true);
        await tmp.rename(f.path);
      } catch (e) {
        if (_alive) state = state.copyWith(error: 'Could not save: $e');
      }
    });
    await _writes;
  }

  /// Copies a LoRA GGUF into the models directory after checking its header
  /// through the bridge. Returns the adapter, or throws with the reason.
  Future<LoraAdapter> importFile(String path) async {
    if (state.importing) throw StateError('An import is already running.');
    if (ref.read(sessionBusyProvider)) {
      throw StateError('Stop the current response before importing.');
    }
    state = state.copyWith(importing: true, clearError: true);
    File? partial;
    try {
      final info = await ref.read(llamaEngineProvider).adapterInfo(path);
      final type = (info['adapterType'] as String?) ?? '';
      final general = (info['type'] as String?) ?? '';
      if (type != 'lora' && general != 'adapter') {
        throw StateError(
          'This GGUF is not a LoRA adapter (general.type "$general"). Convert with convert_lora_to_gguf.py.',
        );
      }
      final hash = await ModelStorage.validateAndHash(path);
      final id = 'lora-${hash.substring(0, 20)}';
      final fileName = '$id.gguf';
      final destination = await ModelStorage.modelFile(fileName);
      if (!await destination.exists()) {
        partial = File('${destination.path}.part');
        await File(path).copy(partial.path);
        if (await ModelStorage.validateAndHash(partial.path) != hash) {
          throw StateError('Import changed while copying. Try again.');
        }
        await ModelStorage.excludeFromICloud(partial);
        await partial.rename(destination.path);
        partial = null;
      }
      final name = (info['name'] as String?)?.trim();
      final adapter = LoraAdapter(
        id: id,
        name: name == null || name.isEmpty
            ? p.basenameWithoutExtension(path)
            : name,
        fileName: fileName,
        architecture: (info['architecture'] as String?) ?? '',
        alpha: (info['alpha'] as num?)?.toDouble() ?? 0,
        sha256: hash,
        sizeBytes: await destination.length(),
        importedAt: DateTime.now(),
      );
      if (_alive) {
        state = state.copyWith(
          adapters: [
            ...state.adapters.where((a) => a.id != adapter.id),
            adapter,
          ],
        );
        await _save();
      }
      return adapter;
    } catch (e) {
      if (_alive) state = state.copyWith(error: '$e');
      rethrow;
    } finally {
      if (partial != null && await partial.exists()) await partial.delete();
      if (_alive) state = state.copyWith(importing: false);
    }
  }

  Future<void> remove(String adapterId) async {
    final a = state.byId(adapterId);
    if (a == null) return;
    if (ref.read(sessionBusyProvider)) {
      throw StateError('Stop the current response before deleting.');
    }
    // The file may be memory-mapped by a loaded model: unload first.
    if (state.attachments.values.any(
      (l) => l.any((x) => x.adapterId == a.id),
    )) {
      await ref.read(llamaEngineProvider).unload();
    }
    await ModelStorage.delete(a.fileName);
    state = state.copyWith(
      adapters: state.adapters.where((x) => x.id != adapterId).toList(),
      attachments: {
        for (final e in state.attachments.entries)
          if (e.value.any((x) => x.adapterId != adapterId))
            e.key: e.value.where((x) => x.adapterId != adapterId).toList(),
      },
    );
    await _save();
  }

  /// Attaches (or re-scales) an adapter on a model. The next load applies
  /// it; the engine reloads on its own when the configuration changed.
  Future<void> attach(String modelId, String adapterId, double scale) async {
    final current = state.of(modelId).where((a) => a.adapterId != adapterId);
    state = state.copyWith(
      attachments: {
        ...state.attachments,
        modelId: [...current, AdapterAttachment(adapterId, scale.clamp(-2, 2))],
      },
    );
    await _save();
  }

  Future<void> detach(String modelId, String adapterId) async {
    final rest = state.of(modelId).where((a) => a.adapterId != adapterId);
    final next = Map<String, List<AdapterAttachment>>.from(state.attachments);
    if (rest.isEmpty) {
      next.remove(modelId);
    } else {
      next[modelId] = rest.toList();
    }
    state = state.copyWith(attachments: next);
    await _save();
  }

  /// File paths and scales the engine needs for [modelId].
  Future<List<({String path, double scale})>> resolved(String modelId) async {
    await ready;
    final out = <({String path, double scale})>[];
    for (final att in state.of(modelId)) {
      final a = state.byId(att.adapterId);
      if (a == null) continue;
      final f = await ModelStorage.modelFile(a.fileName);
      if (await f.exists()) out.add((path: f.path, scale: att.scale));
    }
    return out;
  }
}

final adaptersProvider = NotifierProvider<AdaptersNotifier, AdaptersState>(
  AdaptersNotifier.new,
);
