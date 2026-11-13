import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'image_gen_imports.dart';

/// The last model chosen in each Create mode, remembered across restarts so
/// a user who picked a video or a second upscaler does not have to pick it
/// again on every launch.
class ImageGenPreferences {
  final Map<ImageGenMode, String> preferred;
  final ImageGenMode? lastMode;

  const ImageGenPreferences({this.preferred = const {}, this.lastMode});

  String? of(ImageGenMode mode) => preferred[mode];
}

class ImageGenPreferencesNotifier extends Notifier<ImageGenPreferences> {
  static const prefsKey = 'imageGenPreferredModels';
  SharedPreferences? _prefs;
  Future<void>? _ready;
  bool _alive = true;

  Future<void> get ready {
    final pending = _ready;
    if (pending != null) return pending;
    return _ready = _load();
  }

  @override
  ImageGenPreferences build() {
    _alive = true;
    ref.onDispose(() => _alive = false);
    _ready = _load();
    return const ImageGenPreferences();
  }

  Future<SharedPreferences> _store() async {
    final loaded = _prefs;
    if (loaded != null) return loaded;
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    return prefs;
  }

  Future<void> _load() async {
    try {
      final raw = (await _store()).getString(prefsKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final preferred = <ImageGenMode, String>{};
      for (final mode in ImageGenMode.values) {
        final id = decoded[mode.name];
        if (id is String && id.isNotEmpty) preferred[mode] = id;
      }
      final last = ImageGenMode.values.asNameMap()[decoded['last']];
      if (_alive) {
        state = ImageGenPreferences(preferred: preferred, lastMode: last);
      }
    } on Exception {
      // Unreadable preferences: Create starts with the first built-in model.
    }
  }

  /// Remembers the model to pick when [mode] is opened again.
  Future<void> remember(ImageGenMode mode, String modelId) async {
    await ready;
    if (!_alive) return;
    state = ImageGenPreferences(
      preferred: {...state.preferred, mode: modelId},
      lastMode: mode,
    );
    await _save();
  }

  /// Remembers the mode itself (for example switching to Upscale before a
  /// picture is chosen).
  Future<void> rememberMode(ImageGenMode mode) async {
    await ready;
    if (!_alive || state.lastMode == mode) return;
    state = ImageGenPreferences(preferred: state.preferred, lastMode: mode);
    await _save();
  }

  Future<void> _save() async {
    try {
      await (await _store()).setString(
        prefsKey,
        jsonEncode({
          if (state.lastMode != null) 'last': state.lastMode!.name,
          for (final entry in state.preferred.entries)
            entry.key.name: entry.value,
        }),
      );
    } on Exception {
      // Kept in memory for this session.
    }
  }
}

final imageGenPreferencesProvider =
    NotifierProvider<ImageGenPreferencesNotifier, ImageGenPreferences>(
      ImageGenPreferencesNotifier.new,
    );
