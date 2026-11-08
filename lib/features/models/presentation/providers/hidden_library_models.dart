import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/prefs_rescue.dart';

const _kHiddenKey = 'hidden_library_models_v1';

/// Catalog models the user removed from "Available to download". Built-in
/// catalog rows are re-seeded on every start, so they are hidden by id
/// instead of deleted; Restore brings them all back.
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
    } catch (_) {}
  }
}

final hiddenLibraryModelsProvider =
    NotifierProvider<HiddenLibraryModelsNotifier, Set<String>>(
      HiddenLibraryModelsNotifier.new,
    );
