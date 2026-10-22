import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/storage/prefs_rescue.dart';
import 'package:uuid/uuid.dart';

import '../../domain/preset.dart';

const _kPresetsKey = 'presets_v1';

class PresetsState {
  /// Built-ins first, then the user's own.
  final List<Preset> presets;
  final String activeId;
  const PresetsState({
    this.presets = Preset.builtIns,
    this.activeId = 'general',
  });

  Preset get active =>
      presets.where((p) => p.id == activeId).firstOrNull ?? Preset.general;

  PresetsState copyWith({List<Preset>? presets, String? activeId}) =>
      PresetsState(
        presets: presets ?? this.presets,
        activeId: activeId ?? this.activeId,
      );
}

/// User presets and the active choice, persisted with the settings store.
class PresetsNotifier extends Notifier<PresetsState> {
  SharedPreferences? _prefs;
  late Future<void> ready;
  bool _alive = true;

  @override
  PresetsState build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(_load);
    return const PresetsState();
  }

  Future<void> _load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final raw = _prefs!.getString(_kPresetsKey);
      if (raw == null || !_alive) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final own = [
        for (final e in (j['presets'] as List? ?? const []))
          if (e is Map) Preset.fromJson(Map<String, dynamic>.from(e)),
      ];
      final active = j['activeId'] as String? ?? 'general';
      final all = [...Preset.builtIns, ...own];
      state = PresetsState(
        presets: all,
        activeId: all.any((p) => p.id == active) ? active : 'general',
      );
    } catch (_) {
      // Unreadable store: built-ins only; the user's presets are kept aside.
      await PrefsRescue.keepUnreadable(_prefs, _kPresetsKey);
    }
  }

  Future<void> _save() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(
        _kPresetsKey,
        jsonEncode({
          'presets': [
            for (final p in state.presets)
              if (!p.builtIn) p.toJson(),
          ],
          'activeId': state.activeId,
        }),
      );
    } catch (_) {}
  }

  Future<void> activate(String id) async {
    state = state.copyWith(activeId: id);
    await _save();
  }

  Future<Preset> create(Preset draft) async {
    final p = Preset(
      id: const Uuid().v4(),
      name: draft.name.trim().isEmpty ? 'Preset' : draft.name.trim(),
      emoji: draft.emoji.trim().isEmpty ? '✨' : draft.emoji.trim(),
      systemPrompt: draft.systemPrompt,
      temperature: draft.temperature,
      thinking: draft.thinking,
      webMode: draft.webMode,
    );
    state = state.copyWith(presets: [...state.presets, p], activeId: p.id);
    await _save();
    return p;
  }

  Future<void> update(Preset p) async {
    if (p.builtIn) return;
    state = state.copyWith(
      presets: [for (final x in state.presets) x.id == p.id ? p : x],
    );
    await _save();
  }

  Future<void> remove(String id) async {
    final p = state.presets.where((x) => x.id == id).firstOrNull;
    if (p == null || p.builtIn) return;
    state = state.copyWith(
      presets: state.presets.where((x) => x.id != id).toList(),
      activeId: state.activeId == id ? 'general' : state.activeId,
    );
    await _save();
  }

  /// A copy of a built-in the user can edit.
  Future<Preset> duplicate(Preset source) => create(
    Preset(
      id: '',
      name: '${source.name} (copy)',
      emoji: source.emoji,
      systemPrompt: source.systemPrompt,
      temperature: source.temperature,
      thinking: source.thinking,
      webMode: source.webMode,
    ),
  );
}

final presetsProvider = NotifierProvider<PresetsNotifier, PresetsState>(
  PresetsNotifier.new,
);
