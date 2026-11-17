import 'package:flutter/material.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';

/// Context length: Auto (the recommended choice, owner 2026-11-16) or a
/// length set by hand. Off shows the caller's slider below.
class ContextAutoRow extends StatelessWidget {
  const ContextAutoRow({
    super.key,
    required this.label,
    required this.auto,
    required this.onChanged,
    this.loaded,
  });

  final String label;
  final bool auto;
  final ValueChanged<bool> onChanged;

  /// The context the loaded model got, shown while Auto is on.
  final int? loaded;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final shown = loaded;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Stacked so it fits the narrow inspector column.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.label),
                  Text(
                    t.contextAutoLabel,
                    style: context.text.small.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              key: const Key('context-auto'),
              value: auto,
              onChanged: onChanged,
            ),
          ],
        ),
        if (auto)
          Text(
            shown != null && shown > 0
                ? t.contextAutoLoaded(_tokens(shown))
                : t.contextAutoHint,
            style: context.text.caption.copyWith(color: c.textFaint),
          ),
      ],
    );
  }

  static String _tokens(int n) =>
      n >= 1024 && n % 1024 == 0 ? '${n ~/ 1024}K' : '$n';
}
