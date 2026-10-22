import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/storage/prefs_rescue.dart';

import '../../domain/settings_scope.dart';

const _kProfilesKey = 'model_profiles_v1';
const _kThinkingOffKey = 'thinking_off_profiles_2026_09_28';

/// Per-model setting overrides (roadmap P1.4 "model profile" layer): a
/// map from catalog/import id to a partial settings JSON. A profile follows
/// the model wherever it is used; chats and presets layer on top of it.
class ModelProfilesNotifier
    extends Notifier<Map<String, Map<String, dynamic>>> {
  SharedPreferences? _prefs;
  late Future<void> ready;
  bool _alive = true;
  Future<void> _writes = Future.value();

  @override
  Map<String, Map<String, dynamic>> build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const {};
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_kProfilesKey);
      // Review 2026-09-28: every model starts without thinking (the
      // Think pill turns it on per chat), so a profile's saved "on" is
      // dropped once, like the global switch's.
      final migrate = _prefs!.getBool(_kThinkingOffKey) != true;
      if (migrate) await _prefs!.setBool(_kThinkingOffKey, true);
      if (raw == null || !_alive) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      final profiles = {
        for (final e in j.entries)
          if (e.value is Map)
            e.key.toString(): Map<String, dynamic>.of(
              SettingsResolver.sanitize(
                Map<String, dynamic>.from(e.value as Map),
              ),
            ),
      };
      if (migrate) {
        for (final p in profiles.values) {
          if (p['thinkingModeEnabled'] == true) p.remove('thinkingModeEnabled');
        }
        profiles.removeWhere((_, p) => p.isEmpty);
        await _prefs!.setString(_kProfilesKey, jsonEncode(profiles));
      }
      if (!_alive) return;
      state = profiles;
    } catch (_) {
      // Unreadable profiles fall back to none; the base settings still
      // apply and the stored profiles are kept aside.
      await PrefsRescue.keepUnreadable(_prefs, _kProfilesKey);
    }
  }

  Map<String, dynamic> of(String modelId) => state[modelId] ?? const {};

  /// Replaces the profile of [modelId]; an empty map removes it.
  Future<void> set(String modelId, Map<String, dynamic> overrides) async {
    final clean = SettingsResolver.sanitize(overrides);
    final next = Map<String, Map<String, dynamic>>.from(state);
    if (clean.isEmpty) {
      next.remove(modelId);
    } else {
      next[modelId] = clean;
    }
    state = next;
    final encoded = jsonEncode(next);
    _writes = _writes.then((_) async {
      try {
        _prefs ??= await SharedPreferences.getInstance();
        await _prefs!.setString(_kProfilesKey, encoded);
      } catch (_) {}
    });
    await _writes;
  }

  Future<void> setKey(String modelId, String key, Object? value) => set(
    modelId,
    {...of(modelId), key: value}..removeWhere((k, v) => v == null),
  );

  Future<void> clear(String modelId) => set(modelId, const {});
}

final modelProfilesProvider =
    NotifierProvider<ModelProfilesNotifier, Map<String, Map<String, dynamic>>>(
      ModelProfilesNotifier.new,
    );
