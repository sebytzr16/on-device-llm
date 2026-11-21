import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/storage/prefs_rescue.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../settings/presentation/providers/effective_settings_provider.dart';
import 'chat_provider.dart';

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
    final previous = state;
    var refused = false;
    if (ref.read(chatProvider).chatId == chatId) {
      final confirmation = requestWebModeChange(
        ref.container,
        SettingsChange(changingPin: true, pin: modelId),
      );
      if (confirmation != null) {
        final allowed = await confirmation;
        if (!_alive ||
            !identical(state, previous) ||
            ref.read(chatProvider).chatId != chatId) {
          return;
        }
        refused = !allowed;
      }
    }
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
    } catch (e, st) {
      quietFailure('chat_model_pins:54', e, st);
    }
    if (refused && modelId != null && _alive) {
      // "Stay local" keeps the pin the user chose and takes web research off
      // for this chat, like a new chat stays local (review 2026-11-20
      // finding 20) instead of silently dropping the pin.
      try {
        await ref.read(chatProvider.notifier).setChatOverrides({
          ...ref.read(chatOverridesProvider),
          'webMode': 'off',
        });
      } catch (e, st) {
        quietFailure('chat_model_pins:84', e, st);
      }
      ref.read(islandProvider.notifier).toast(appStrings.chatPinStaysLocal);
    }
  }
}

final chatModelPinsProvider =
    NotifierProvider<ChatModelPinsNotifier, Map<String, String>>(
      ChatModelPinsNotifier.new,
    );
