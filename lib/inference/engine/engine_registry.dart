import 'dart:io';

import '../../features/models/domain/entities/model_info.dart';
import 'engine_descriptor.dart';

/// Registration order defines the default when two engines claim a format:
/// llama.cpp comes first, so an installed optional pack (ik_llama.cpp) is only
/// used after the user picks it for that model.
class EngineRegistry {
  EngineRegistry({
    required this.platform,
    Iterable<EngineDescriptor> engines = knownTextEngines,
    Set<String> installedPacks = const {},
    Map<String, bool> deviceSupport = const {},
    Map<String, String> overrides = const {},
  }) : engines = List.unmodifiable(engines),
       installedPacks = Set.unmodifiable(installedPacks),
       deviceSupport = Map.unmodifiable(deviceSupport),
       overrides = Map.unmodifiable(overrides);

  final String platform;
  final List<EngineDescriptor> engines;
  final Set<String> installedPacks;
  final Map<String, bool> deviceSupport;
  final Map<String, String> overrides;

  bool isAvailable(EngineDescriptor engine) =>
      (deviceSupport[engine.id] ?? engine.platforms.contains(platform)) &&
      (engine.distribution == EngineDistribution.bundled ||
          installedPacks.contains(engine.id));

  Iterable<EngineDescriptor> get available => engines.where(isAvailable);

  EngineDescriptor? forPath(String path) =>
      available.where((engine) => engine.claims(path)).firstOrNull ??
      engines.where((engine) => engine.claims(path)).firstOrNull;

  /// An override must claim the file and be available on this device.
  /// Stale overrides fall back to the first available compatible engine.
  EngineDescriptor? resolve(ModelInfo model, {String? overrideId}) {
    final path = model.localPath ?? model.fileName;
    final candidates = available.where((engine) => engine.claims(path));
    final preferred = overrideId ?? overrides[model.id];
    return candidates.where((engine) => engine.id == preferred).firstOrNull ??
        candidates.firstOrNull;
  }

  /// Presentation can describe a known but unavailable engine. Keep the
  /// historical llama.cpp default for legacy model records without a suffix.
  EngineDescriptor descriptorFor(ModelInfo? model) => model == null
      ? llamaCppEngine
      : resolve(model) ??
            forPath(model.localPath ?? model.fileName) ??
            llamaCppEngine;
}

final defaultEngineRegistry = EngineRegistry(
  platform: Platform.operatingSystem,
);
