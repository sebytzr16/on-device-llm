import '../../../../core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../settings/presentation/widgets/settings_widgets.dart';
import '../../../../core/platform/device_info.dart';
import '../../../benchmark/benchmark.dart';
import '../../../benchmark/benchmark_dialog.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../providers/model_manager_provider.dart';

class ModelReadinessPage extends ConsumerWidget {
  const ModelReadinessPage({super.key});

  static String _gb(int bytes) =>
      '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(deviceMemoryProvider).value;
    final storage = ref.watch(deviceStorageProvider).value;
    final models = ref.watch(modelManagerProvider).catalog;
    final benchmarks = ref.watch(benchmarkProvider).results;
    final settings = ref.watch(settingsProvider);
    final installed = models.where((model) => model.isDownloaded).toList();
    final usedBytes = installed.fold<int>(
      0,
      (total, model) => total + model.sizeBytes,
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.uiModelReadinessPageModelReadiness),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(AppDesign.lg),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: SettingsSection(
                    label: context.l10n.uiModelReadinessPageDeviceCapacity,
                    children: [
                      SettingsRow(
                        leading: const Icon(Icons.memory_rounded),
                        title: Text(
                          context.l10n.uiModelReadinessPagePhysicalRAM,
                        ),
                        subtitle: Text(
                          memory == null
                              ? context.l10n.readinessUnavailable
                              : context.l10n.readinessMemory(
                                  _gb(memory.totalBytes),
                                  _gb(memory.availableBytes),
                                ),
                        ),
                      ),
                      SettingsRow(
                        leading: const Icon(Icons.sd_storage_outlined),
                        title: Text(
                          context.l10n.uiModelReadinessPageModelStorageVolume,
                        ),
                        subtitle: Text(
                          storage == null
                              ? context.l10n.storageUnavailable
                              : context.l10n.readinessStorage(
                                  _gb(storage.availableBytes),
                                  _gb(storage.totalBytes),
                                ),
                        ),
                      ),
                      SettingsRow(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(
                          context
                              .l10n
                              .uiModelReadinessPageInstalledModelWeights,
                        ),
                        subtitle: Text(
                          context.l10n.readinessInstalledWeights(
                            _gb(usedBytes),
                            installed.length,
                          ),
                        ),
                      ),
                      SettingsRow(
                        leading: const Icon(Icons.developer_board_outlined),
                        title: Text(
                          context
                              .l10n
                              .uiModelReadinessPageCurrentContextAndBackend,
                        ),
                        subtitle: Text(
                          context.l10n.readinessContext(
                            settings.contextSize,
                            settings.backend.name,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SliverToBoxAdapter(
                  child: SettingsSection(
                    label: context.l10n.uiModelReadinessPageModels,
                  ),
                ),
                SettingsGroup.sliver(
                  itemCount: models.length,
                  itemBuilder: (context, index) {
                    final model = models[index];
                    return SettingsRow(
                      title: Text(model.displayName),
                      subtitle: Text(
                        [
                          model.isDownloaded
                              ? context.l10n.readinessInstalled
                              : context.l10n.readinessDownload(model.sizeLabel),
                          if (memory != null)
                            memory.fits(model.sizeBytes)
                                ? context.l10n.readinessRamFits
                                : context.l10n.readinessRamMayNotFit,
                          if (!model.isDownloaded && storage != null)
                            storage.availableBytes > model.sizeBytes * 1.1
                                ? context.l10n.readinessDiskAvailable
                                : context.l10n.readinessDiskInsufficient,
                          if (benchmarks[model.id] != null)
                            context.l10n.readinessMeasured(
                              benchmarks[model.id]!.decodeTps.toStringAsFixed(
                                1,
                              ),
                            ),
                        ].join(' · '),
                      ),
                      isThreeLine: true,
                      trailing: model.isDownloaded
                          ? IconButton(
                              tooltip: context.l10n.benchmark,
                              icon: const Icon(Icons.speed_outlined),
                              onPressed: () =>
                                  showBenchmarkDialog(context, ref, model),
                            )
                          : null,
                    );
                  },
                ),
                SliverList.list(
                  children: [
                    Text(
                      context.l10n.uiModelReadinessPageRAMFitIsARoughEstimate,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
