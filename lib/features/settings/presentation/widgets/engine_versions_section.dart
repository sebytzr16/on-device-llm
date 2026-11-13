import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/platform/desktop_host.dart';
import '../../../../core/platform/engine_versions.dart';
import '../../../../core/providers/shared_providers.dart';
import 'settings_widgets.dart';

/// Runtime facts (bundled CUDA DLLs, NVIDIA driver); overridable in tests.
final engineRuntimeInfoProvider = FutureProvider<EngineRuntimeInfo>(
  // Phones have no bundled CUDA or nvidia-smi: probe on the desktop only.
  (ref) => DesktopHost.active
      ? EngineRuntimeInfo.probe()
      : Future.value(const EngineRuntimeInfo()),
);

/// Update checker; a test overrides it with a fake HTTP fetch.
final engineUpdateCheckerProvider = Provider<EngineUpdateChecker>(
  (ref) => EngineUpdateChecker(),
);

/// Bridge library the loaded model runs on (desktop file name), if any.
final loadedEngineLibraryProvider = Provider.autoDispose<String?>((ref) {
  try {
    return ref.read(llamaEngineProvider).library ??
        ref.read(llamaEstimatorProvider).library;
  } catch (_) {
    return null;
  }
});

/// Versions of the bundled engines plus a manual "check for updates".
/// Nothing touches the network until the button is pressed.
class EngineVersionsSection extends ConsumerStatefulWidget {
  const EngineVersionsSection({super.key});

  @override
  ConsumerState<EngineVersionsSection> createState() =>
      _EngineVersionsSectionState();
}

class _EngineVersionsSectionState extends ConsumerState<EngineVersionsSection> {
  bool _checking = false;
  List<EngineUpdateItem>? _result;

  Future<void> _check() async {
    setState(() => _checking = true);
    List<EngineUpdateItem> items;
    try {
      items = await ref.read(engineUpdateCheckerProvider).check();
    } catch (_) {
      items = const [];
    }
    if (!mounted) return;
    setState(() {
      _checking = false;
      _result = items;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final mono = context.text.mono.copyWith(color: c.textMuted);
    final runtime = ref.watch(engineRuntimeInfoProvider).value;
    final cuda = runtime?.cudaRuntimeMajor;
    final driver = runtime?.driverVersion;
    final required = cuda == null ? null : minDriverForCudaMajor(cuda);
    final ok = driverSupports(driver, required);

    Widget row(IconData icon, String title, String value) => SettingsRow(
      leading: Icon(icon),
      title: Text(title),
      trailing: Text(value, style: mono),
    );

    return SettingsSection(
      label: t.engineVersionsTitle,
      children: [
        row(
          Icons.memory_rounded,
          t.engineLlamaCppBuild,
          '${EnginePins.llamaCppTag} (${EnginePins.llamaCppCommit.substring(0, 8)})',
        ),
        row(
          Icons.image_outlined,
          t.engineSdCppRevision,
          EnginePins.sdCommit.substring(0, 8),
        ),
        if (cuda != null || driver != null) ...[
          row(
            Icons.developer_board_rounded,
            t.engineCudaRuntime,
            cuda ?? t.engineNotDetected,
          ),
          row(
            Icons.settings_applications_outlined,
            t.engineNvidiaDriver,
            driver ?? t.engineNotDetected,
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.md,
            vertical: AppDesign.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                onPressed: _checking ? null : _check,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.system_update_alt_rounded),
                label: Text(
                  _checking ? t.engineChecking : t.engineCheckUpdates,
                ),
              ),
              if (_result != null) ...[
                const SizedBox(height: AppDesign.sm),
                for (final i in _result!) Text(_describe(t, i)),
                if (cuda != null &&
                    driver != null &&
                    required != null &&
                    ok != null)
                  Text(
                    ok
                        ? t.engineDriverOk(driver, cuda, required)
                        : t.engineDriverTooOld(driver, cuda, required),
                  ),
                if (cuda != null) Text(t.engineCudaNote),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static String _describe(dynamic t, EngineUpdateItem i) => switch (i.state) {
    EngineUpdateState.upToDate => t.engineUpToDate(i.name),
    EngineUpdateState.newer => t.engineNewerAvailable(
      i.name,
      i.latest ?? '',
      i.bundled,
    ),
    EngineUpdateState.unknown => t.engineUpdateUnknown(i.name),
    EngineUpdateState.offline => t.engineUpdateOffline(i.name),
  };
}
