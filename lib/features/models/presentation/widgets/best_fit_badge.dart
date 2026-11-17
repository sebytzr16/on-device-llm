import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';

/// "Best for this device" on the top Recommended model when it fits
/// (first-run guide, owner 2026-11-16).
class BestFitBadge extends StatelessWidget {
  const BestFitBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      key: const Key('best-fit-badge'),
      padding: const EdgeInsets.fromLTRB(6, 2, 8, 2),
      decoration: BoxDecoration(
        color: c.accent.withValues(alpha: 0.14),
        borderRadius: AppDesign.radius(AppDesign.rFull),
        border: Border.all(color: c.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 12, color: c.accent),
          const SizedBox(width: 4),
          Text(
            context.l10n.bestFitBadge,
            style: context.text.caption.copyWith(
              color: c.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
