import '../../../../core/platform/device_info.dart';
import '../../../models/domain/entities/model_catalog.dart';
import '../../../models/domain/entities/model_info.dart';

bool _fits(DeviceMemory? memory, ModelInfo m) =>
    memory == null ||
    memory.fits(m.sizeBytes, minRamGb: catalogMeta[m.id]?.minRamGb ?? 0);

/// The starter we suggest: Qwen3.5 4B on 8 GB+, 2B on 6 GB+, else 0.8B —
/// each only if it fits. Unknown RAM is treated as small.
ModelInfo recommendStarter(DeviceMemory? memory, List<ModelInfo> catalog) {
  final gb = memory?.totalGb ?? 0;
  final preferred = [
    if (gb >= 8) 'qwen35-4b-iq4nl',
    if (gb >= 6) 'qwen35-2b-iq4nl',
    'qwen35-0.8b-q8_0',
  ];
  ModelInfo? byId(String id) => catalog.where((m) => m.id == id).firstOrNull;
  for (final id in preferred) {
    final m = byId(id);
    if (m != null && _fits(memory, m)) return m;
  }
  final reasoning =
      catalog
          .where(
            (m) => catalogMeta[m.id]?.reasoning == true && _fits(memory, m),
          )
          .toList()
        ..sort(
          (a, b) => catalogMeta[b.id]!.parameterCountB.compareTo(
            catalogMeta[a.id]!.parameterCountB,
          ),
        );
  return reasoning.firstOrNull ?? byId('qwen35-0.8b-q8_0') ?? catalog.first;
}

/// Alternatives shown under the recommendation.
List<ModelInfo> starterAlternatives(
  DeviceMemory? memory,
  List<ModelInfo> catalog,
  ModelInfo selected,
) => catalog.where((m) => m.id != selected.id).toList();
