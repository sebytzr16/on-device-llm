import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/storage/prefs_rescue.dart';

import 'domain/prompt_shortcut.dart';

const _kShortcutsKey = 'prompt_shortcuts_v1';

/// Built-in shortcuts plus the user's own (which may replace a built-in of
/// the same name). Stored on the phone with the other preferences.
class PromptShortcutsNotifier extends Notifier<List<PromptShortcut>> {
  SharedPreferences? _prefs;
  late Future<void> ready;
  bool _alive = true;

  @override
  List<PromptShortcut> build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return PromptShortcut.builtIns;
  }

  List<PromptShortcut> get own => [
    for (final s in state)
      if (!s.builtIn) s,
  ];

  static List<PromptShortcut> merge(List<PromptShortcut> own) => [
    ...own,
    for (final b in PromptShortcut.builtIns)
      if (!own.any((o) => o.name == b.name)) b,
  ];

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_kShortcutsKey);
      if (raw == null || !_alive) return;
      final own = [
        for (final e in (jsonDecode(raw) as List? ?? const []))
          ?PromptShortcut.fromJson(e),
      ];
      state = merge(own);
    } catch (_) {
      // Unreadable store: the built-ins still work; the user's shortcuts
      // are kept aside.
      await PrefsRescue.keepUnreadable(_prefs, _kShortcutsKey);
    }
  }

  Future<void> _save(List<PromptShortcut> own) async {
    state = merge(own);
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(
        _kShortcutsKey,
        jsonEncode([for (final s in own) s.toJson()]),
      );
    } catch (_) {}
  }

  /// Adds or replaces (by name, [previousName] when renamed) a shortcut.
  Future<void> put(PromptShortcut shortcut, {String? previousName}) => _save([
    for (final s in own)
      if (s.name != shortcut.name && s.name != previousName) s,
    shortcut,
  ]);

  /// Removes the user's shortcut; a built-in it replaced comes back.
  Future<void> remove(String name) => _save([
    for (final s in own)
      if (s.name != name) s,
  ]);
}

final promptShortcutsProvider =
    NotifierProvider<PromptShortcutsNotifier, List<PromptShortcut>>(
      PromptShortcutsNotifier.new,
    );
