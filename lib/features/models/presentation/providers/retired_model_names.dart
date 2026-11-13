import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/storage/prefs_rescue.dart';
import '../../domain/entities/model_info.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

const _kRetiredKey = 'retired_model_names_v1';

/// Names of models the user deleted (model id → display name). Imported and
/// Hub models have hash ids, so old answers keep showing the model's name
/// instead of "local-3f9a…" once its row is gone.
class RetiredModelNamesNotifier extends Notifier<Map<String, String>> {
  SharedPreferences? _prefs;
  late Future<void> ready;
  bool _alive = true;

  @override
  Map<String, String> build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_kRetiredKey);
      if (raw == null || !_alive) return;
      final j = jsonDecode(raw);
      if (j is Map) {
        state = {
          for (final e in j.entries)
            if (e.value is String) '${e.key}': e.value as String,
          ...state,
        };
      }
    } catch (_) {
      await PrefsRescue.keepUnreadable(_prefs, _kRetiredKey);
    }
  }

  Future<void> remember(String id, String name) async {
    if (name.trim().isEmpty || state[id] == name) return;
    await ready;
    final next = {...state, id: name};
    state = next;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_kRetiredKey, jsonEncode(next));
    } catch (e, st) {
      quietFailure('retired_model_names:52', e, st);
    }
  }
}

final retiredModelNamesProvider =
    NotifierProvider<RetiredModelNamesNotifier, Map<String, String>>(
      RetiredModelNamesNotifier.new,
    );

/// The name shown for the model that wrote an answer: the library's name,
/// else the name it had when deleted, else [removed]. Never a raw hash id.
String modelLabel(
  String? id, {
  required Iterable<ModelInfo> catalog,
  required Map<String, String> retired,
  required String removed,
  String? fallback,
}) {
  if (id != null && id.startsWith('remote:')) {
    final m = id.substring(7);
    return '${m.isEmpty ? 'server model' : m} · remote';
  }
  if (id == null) return fallback ?? removed;
  return catalog.where((m) => m.id == id).firstOrNull?.displayName ??
      retired[id] ??
      removed;
}
