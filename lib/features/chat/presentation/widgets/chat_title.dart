import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';

/// The chat header: "OnDevice" in the headline face, "LLM" in the accent
/// colour, and what answers ([subtitle]: the model, server or chat kind).
class ChatTitle extends StatelessWidget {
  final String subtitle;
  const ChatTitle({super.key, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 21 pt fits beside the three actions; a large font setting shrinks
        // the whole name instead of cutting "LLM" off (tester, 2026-10-20).
        FittedBox(
          key: const Key('app-title'),
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text.rich(
            TextSpan(
              text: context.l10n.appTitle,
              children: [
                TextSpan(
                  text: ' LLM',
                  style: TextStyle(color: c.accent),
                ),
              ],
            ),
            style: context.text.headline.copyWith(fontSize: 21),
            maxLines: 1,
          ),
        ),
        Text(
          subtitle,
          style: context.text.caption.copyWith(color: c.textFaint),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
