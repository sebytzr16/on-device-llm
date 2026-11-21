import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/quiet_failure.dart';
import '../../core/platform/engine_versions.dart';
import '../../core/providers/shared_providers.dart';
import '../../core/storage/prefs_rescue.dart';
import '../../features/settings/domain/entities/inference_settings.dart';
import 'engine_descriptor.dart';
import 'engine_registry.dart';
import 'text_engine.dart';

const _kEngineOverridesKey = 'engine_overrides_v1';

/// Per-model engine choices (model id → engine id), stored with the other
/// preferences like `chat_model_pins_v1`: a model keeps its engine across
/// restarts. Missing entries use format order.
class EngineOverridesNotifier extends Notifier<Map<String, String>> {
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
      final raw = _prefs!.getString(_kEngineOverridesKey);
      if (raw == null || !_alive) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        state = {
          for (final entry in decoded.entries)
            if (entry.value is String) '${entry.key}': entry.value as String,
        };
      }
    } catch (_) {
      await PrefsRescue.keepUnreadable(_prefs, _kEngineOverridesKey);
    }
  }

  /// Chooses [engineId] for [modelId]; null removes the choice.
  Future<void> set(String modelId, String? engineId) async {
    // A pick made while the stored choices are still loading would be
    // overwritten by them: wait for the load, then merge on top of it.
    await ready;
    final next = Map<String, String>.from(state);
    if (engineId == null) {
      next.remove(modelId);
    } else {
      next[modelId] = engineId;
    }
    state = next;
    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setString(_kEngineOverridesKey, jsonEncode(next));
    } catch (e, st) {
      quietFailure('engine_overrides:set', e, st);
    }
  }
}

final engineOverridesProvider =
    NotifierProvider<EngineOverridesNotifier, Map<String, String>>(
      EngineOverridesNotifier.new,
    );

/// Engine IDs whose signed engine pack is installed and verified. The engine
/// updater fills this after its startup scan, so a packaged engine (today
/// ik_llama.cpp) is offered only once its DLLs are really on disk. Empty means
/// bundled engines only.
final installedEnginePacksProvider = StateProvider<Set<String>>(
  (ref) => const {},
);

/// True when this app version knows which build of the optional ik_llama.cpp
/// engine to offer. While the pin is all zeros the engine, its picker and its
/// install row stay out of the UI. Overridable in tests.
final ikEngineAvailableProvider = Provider<bool>(
  (ref) => EnginePins.ikLlamaPinned,
);

/// The host platform the registry filters engines by; a test overrides it.
final enginePlatformProvider = Provider<String>(
  (ref) => Platform.operatingSystem,
);

final engineRegistryProvider = Provider<EngineRegistry>((ref) {
  return EngineRegistry(
    platform: ref.watch(enginePlatformProvider),
    installedPacks: ref.watch(installedEnginePacksProvider),
    overrides: ref.watch(engineOverridesProvider),
    deviceSupport: {liteRtLmEngine.id: ref.watch(liteRtAvailableProvider)},
  );
});

/// Used by the Android import affordance and existing device tests.
final liteRtAvailableProvider = Provider<bool>(
  (ref) => liteRtLmEngine.platforms.contains(Platform.operatingSystem),
);

/// Lifecycle for engines that load directly from a file. The llama.cpp
/// bridge retains its existing GGUF planner, progress and hosting handoff.
typedef FileEngine = ({
  TextEngine engine,
  bool Function() isLoaded,
  bool Function(String, InferenceSettings) holdsLoad,
  Future<void> Function(String, InferenceSettings) load,
  Future<void> Function() unload,
});

final fileEngineProviders = <String, Provider<FileEngine>>{
  liteRtLmEngine.id: Provider((ref) {
    final engine = ref.watch(liteRtEngineProvider);
    return (
      engine: engine,
      isLoaded: () => engine.isLoaded,
      holdsLoad: (path, settings) => engine.holdsLoad(
        path,
        settings.liteRtBackend,
        vision: settings.visionEnabled,
      ),
      load: (path, settings) => engine.loadModel(
        path,
        backend: settings.liteRtBackend,
        vision: settings.visionEnabled,
      ),
      unload: engine.unload,
    );
  }),
};

final availableFileEnginesProvider = Provider<List<FileEngine>>((ref) {
  final registry = ref.watch(engineRegistryProvider);
  return [
    for (final engine in registry.engines)
      if (fileEngineProviders[engine.id] case final provider?)
        if (registry.isAvailable(engine)) ref.watch(provider),
  ];
});
