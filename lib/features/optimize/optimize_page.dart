import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_design.dart';
import '../../core/l10n/l10n.dart';
import '../../desktop/model_tune_section.dart';
import '../models/domain/entities/model_info.dart';
import '../settings/presentation/providers/effective_settings_provider.dart';

/// "Optimize for this device" on the phone (owner 2026-11-16): the same
/// measured run as the desktop's Optimize (speed per setup, same-answer
/// check, keeps the current settings when nothing is clearly faster), on
/// a page of its own for the loaded model.
class OptimizePage extends ConsumerWidget {
  const OptimizePage({super.key, required this.model, this.autoStart = false});

  final ModelInfo model;
  final bool autoStart;

  static Future<void> open(
    BuildContext context,
    ModelInfo model, {
    bool autoStart = false,
  }) => Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => OptimizePage(model: model, autoStart: autoStart),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.l10n;
    final settings = ref.watch(effectiveSettingsProvider).effective;
    return Scaffold(
      appBar: AppBar(title: Text(t.optimizeSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.phonePage,
          AppSpace.md,
          AppSpace.phonePage,
          AppSpace.section,
        ),
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.14),
                  borderRadius: AppDesign.radius(AppDesign.rMd),
                ),
                child: Icon(Icons.auto_fix_high_rounded, color: c.accent),
              ),
              const SizedBox(width: AppSpace.row),
              Expanded(
                child: Text(
                  model.displayName,
                  style: context.text.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          ModelOptimizeSection(
            key: ValueKey('optimize-${model.id}'),
            model: model,
            settings: settings,
            autoStart: autoStart,
          ),
        ],
      ),
    );
  }
}
