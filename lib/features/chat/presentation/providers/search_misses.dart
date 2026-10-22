import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/storage/prefs_rescue.dart';

const _kMissesKey = 'search_misses_v1';

/// Questions the user sent to the web by hand after an answer from the
/// model's memory: the phrasings the keyword lists missed. Kept on the
/// phone only, newest first, so they can be copied into
/// `eval/keyword_cases.json` and the lists (`web_terms.dart`) extended.
class SearchMissesNotifier extends Notifier<List<String>> {
  static const maxKept = 200;
  SharedPreferences? _prefs;
  late Future<void> ready;
  bool _alive = true;

  @override
  List<String> build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const [];
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_kMissesKey);
      if (raw == null || !_alive) return;
      state = [
        for (final e in jsonDecode(raw) as List)
          if (e is String) e,
      ];
    } catch (_) {
      await PrefsRescue.keepUnreadable(_prefs, _kMissesKey);
    }
  }

  Future<void> add(String question) async {
    await ready;
    final q = question.trim();
    if (q.isEmpty) return;
    state = [q, ...state.where((e) => e != q)].take(maxKept).toList();
    await _save();
  }

  Future<void> clear() async {
    state = const [];
    await _save();
  }

  Future<void> _save() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_kMissesKey, jsonEncode(state));
    } catch (_) {
      // The in-memory list still works this session.
    }
  }
}

final searchMissesProvider =
    NotifierProvider<SearchMissesNotifier, List<String>>(
      SearchMissesNotifier.new,
    );
