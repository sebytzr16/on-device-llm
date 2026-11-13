import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/prefs_rescue.dart';
import '../../domain/entities/model_catalog.dart';
import '../../domain/entities/model_info.dart';
import 'model_manager_provider.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

const _kHiddenKey = 'hidden_library_models_v1';

/// Catalog models the user removed from "Available to download". Built-in
/// catalog rows are re-seeded on every start, so they are hidden by id
/// instead of deleted. There is no restore (owner 2026-11-12).
class HiddenLibraryModelsNotifier extends Notifier<Set<String>> {
  SharedPreferences? _prefs;
  late Future<void> ready;
  bool _alive = true;

  @override
  Set<String> build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_kHiddenKey);
      if (raw == null || !_alive) return;
      final j = jsonDecode(raw);
      if (j is List) state = {...j.whereType<String>(), ...state};
    } catch (_) {
      await PrefsRescue.keepUnreadable(_prefs, _kHiddenKey);
    }
  }

  Future<void> hide(String id) async {
    await ready;
    if (state.contains(id)) return;
    await _write({...state, id});
  }

  Future<void> restoreAll() async {
    await ready;
    if (state.isEmpty) return;
    await _write(const {});
  }

  Future<void> _write(Set<String> next) async {
    state = next;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_kHiddenKey, jsonEncode(next.toList()));
    } catch (e, st) {
      quietFailure('hidden_library_models:55', e, st);
    }
  }
}

/// Removes a model that is not downloaded from the Recommended list for
/// good (owner 2026-11-12: no restore). Every entry is hidden by id, since
/// the phone and desktop catalogs are both re-seeded on start (a desktop
/// catalog row such as Qwen 3.5 9B also shows on the phone); an entry the
/// user added themselves is deleted from the library too.
Future<void> removeLibraryEntry(
  WidgetRef ref,
  ModelManagerNotifier manager,
  ModelInfo model,
) async {
  await ref.read(hiddenLibraryModelsProvider.notifier).hide(model.id);
  final seeded = [
    ...bundledCatalog,
    ...desktopCatalog,
  ].any((m) => m.id == model.id);
  if (!seeded) await manager.deleteModel(model);
}

final hiddenLibraryModelsProvider =
    NotifierProvider<HiddenLibraryModelsNotifier, Set<String>>(
      HiddenLibraryModelsNotifier.new,
    );
