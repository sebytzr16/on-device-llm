import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/storage/prefs_rescue.dart';

const _kPinsKey = 'chat_model_pins_v1';

/// Models pinned to chats (chat id → model id): a coding chat keeps its
/// coding model whatever the model picker says. Stored with the other
/// preferences; a pin to a model that is no longer downloaded is ignored.
class ChatModelPinsNotifier extends Notifier<Map<String, String>> {
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
      final raw = _prefs!.getString(_kPinsKey);
      if (raw == null || !_alive) return;
      final j = jsonDecode(raw);
      if (j is Map) {
        state = {
          for (final e in j.entries)
            if (e.value is String) '${e.key}': e.value as String,
        };
      }
    } catch (_) {
      await PrefsRescue.keepUnreadable(_prefs, _kPinsKey);
    }
  }

  /// Pins [modelId] to [chatId]; null removes the pin.
  Future<void> set(String chatId, String? modelId) async {
    final next = Map<String, String>.from(state);
    if (modelId == null) {
      next.remove(chatId);
    } else {
      next[chatId] = modelId;
    }
    state = next;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_kPinsKey, jsonEncode(next));
    } catch (_) {}
  }
}

final chatModelPinsProvider =
    NotifierProvider<ChatModelPinsNotifier, Map<String, String>>(
      ChatModelPinsNotifier.new,
    );
