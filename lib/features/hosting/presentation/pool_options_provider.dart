import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../model_pool.dart';

const _kPoolKey = 'server_pool_v1';

/// The desktop server's extra-model options, kept across launches.
class PoolOptionsNotifier extends Notifier<PoolOptions> {
  bool _alive = true;

  @override
  PoolOptions build() {
    ref.onDispose(() => _alive = false);
    unawaited(_load());
    return const PoolOptions();
  }

  Future<void> _load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_kPoolKey);
      if (raw == null || !_alive) return;
      final j = jsonDecode(raw);
      if (j is Map) state = PoolOptions.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {
      /* Defaults. */
    }
  }

  Future<void> togglePinned(String id) {
    final pinned = {...state.pinned};
    if (!pinned.remove(id)) pinned.add(id);
    return set(state.copyWith(pinned: pinned));
  }

  Future<void> set(PoolOptions options) async {
    state = options;
    try {
      await (await SharedPreferences.getInstance()).setString(
        _kPoolKey,
        jsonEncode(options.toJson()),
      );
    } catch (_) {}
  }
}

final poolOptionsProvider = NotifierProvider<PoolOptionsNotifier, PoolOptions>(
  PoolOptionsNotifier.new,
);
