import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/motion/motion.dart';
import '../../../../core/l10n/l10n.dart';

/// The whole turn notice: from the pop-up over the composer, which shows
/// two lines, or from the warning triangle under an answer.
Future<void> showNoticeSheet(
  BuildContext context,
  String notice, {
  bool warning = false,
}) => showMorphSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (sheet) {
    final c = sheet.colors;
    return AppSheet(
      title: sheet.l10n.sheetNotice,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Icon(
                warning ? Icons.warning_amber_rounded : Icons.info_outline,
                size: 18,
                color: warning ? c.warning : c.textFaint,
              ),
            ),
            const SizedBox(width: AppDesign.sm),
            Expanded(
              child: SelectableText(
                notice,
                key: const Key('turn-notice-full'),
                style: sheet.text.body.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ],
    );
  },
);
