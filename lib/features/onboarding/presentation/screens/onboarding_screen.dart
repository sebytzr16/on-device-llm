import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/motion/motion.dart';
import '../../../../core/platform/device_info.dart';
import '../../../../core/providers/first_launch_provider.dart';
import '../../../../data/storage/download_manager.dart';
import '../../../models/domain/entities/model_catalog.dart';
import '../../../models/domain/entities/model_info.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../widgets/onboarding_steps.dart';
import '../../../models/presentation/screens/model_readiness_page.dart';
import '../widgets/starter_model.dart';
import '../../../../core/l10n/l10n.dart';

/// Three skippable steps: privacy promise -> pick a starter model (RAM-aware)
/// -> download -> chat. Finishing or skipping calls `complete()`.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pages = PageController();
  int _step = 0;
  String? _selectedId;
  bool _acknowledged = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _complete() => ref.read(onboardingDoneProvider.notifier).complete();

  void _go(int step) {
    setState(() => _step = step);
    // The next step slides in on the page spring.
    final motion = context.motion;
    _pages.animateToPage(
      step,
      duration: motion.fade(const Duration(milliseconds: 560)),
      curve: SpringCurve(SpringPageTransitionsBuilder.page),
    );
  }

  /// Bundled order and metadata, with per-install facts from the database once
  /// the seed has landed.
  List<ModelInfo> _catalog(ModelManagerState state) => [
    for (final b in bundledCatalog)
      state.catalog.where((m) => m.id == b.id).firstOrNull ?? b,
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(modelManagerProvider);
    final memory = ref.watch(deviceMemoryProvider).value;
    final manager = ref.read(modelManagerProvider.notifier);
    final catalog = _catalog(state);
    final recommended = recommendStarter(memory, catalog);
    final selected =
        catalog.where((m) => m.id == _selectedId).firstOrNull ?? recommended;
    final progress = state.downloads[selected.id];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.xl,
                AppDesign.sm,
                AppDesign.md,
                0,
              ),
              child: Row(
                children: [
                  // The current step's dot stretches out on a spring.
                  for (var i = 0; i < 3; i++)
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: i == _step ? 22 : 6),
                      duration: context.motion.fade(
                        const Duration(milliseconds: 600),
                      ),
                      curve: SpringCurve(AppMotion.pop),
                      builder: (context, width, _) => AnimatedContainer(
                        duration: context.motion.fade(AppMotion.fadeIn),
                        margin: const EdgeInsets.only(right: AppDesign.sm - 2),
                        width: width.clamp(4.0, 30.0),
                        height: 6,
                        decoration: BoxDecoration(
                          color: i == _step ? c.accent : c.hairlineStrong,
                          borderRadius: AppDesign.radius(AppDesign.rFull),
                        ),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _complete,
                    style: TextButton.styleFrom(foregroundColor: c.textMuted),
                    child: Text(context.l10n.skip),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  PrivacyStep(onContinue: () => _go(1)),
                  PickModelStep(
                    selected: selected,
                    recommended: recommended,
                    alternatives: starterAlternatives(
                      memory,
                      catalog,
                      selected,
                    ),
                    memory: memory,
                    acknowledged: _acknowledged,
                    onSelect: (m) => setState(() => _selectedId = m.id),
                    onAcknowledge: (v) => setState(() => _acknowledged = v),
                    onDownload: () {
                      _go(2);
                      unawaited(manager.downloadModel(selected));
                    },
                    onLater: _complete,
                  ),
                  DownloadStep(
                    model: selected,
                    progress: progress,
                    downloaded: selected.isDownloaded,
                    error: progress?.status == DownloadStatus.failed
                        ? progress?.error ?? state.error
                        : state.error,
                    onPause: () => manager.pauseDownload(selected.id),
                    onResume: () => unawaited(manager.downloadModel(selected)),
                    onStart: _complete,
                    onReadiness: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ModelReadinessPage(),
                      ),
                    ),
                    onSkip: _complete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
