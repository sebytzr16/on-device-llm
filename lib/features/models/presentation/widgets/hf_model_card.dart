import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../data/network/hugging_face.dart';
import '../providers/hf_repository_provider.dart';
import 'model_tags.dart';

class HfModelCard extends ConsumerWidget {
  final HfRepoFiles files;
  const HfModelCard({super.key, required this.files});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (files.repo, files.revision);
    final card = ref.watch(hfReadmeProvider(key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ModelTag(context.l10n.licenseLabel(files.license)),
            if (files.parameterCount case final count?)
              ModelTag(
                context.l10n.modelParameters(
                  '${(count / 1e9).toStringAsFixed(1)}B',
                ),
              )
            else
              ModelTag(context.l10n.modelParameters(context.l10n.modelUnknown)),
            if (files.contextLength case final count?)
              ModelTag(context.l10n.modelContextTokens('$count'))
            else
              ModelTag(
                '${context.l10n.modelContextLength}: ${context.l10n.modelUnknown}',
              ),
          ],
        ),
        const SizedBox(height: 12),
        card.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.modelCardUnavailable,
                style: context.text.small,
              ),
              TextButton(
                onPressed: () => ref.invalidate(hfReadmeProvider(key)),
                child: Text(context.l10n.modelCardRetry),
              ),
            ],
          ),
          data: (text) => MarkdownBody(
            data: text,
            selectable: true,
            // Model cards are untrusted content. Images and links never fetch.
            imageBuilder: (_, _, _) => const SizedBox.shrink(),
            styleSheet: MarkdownStyleSheet.fromTheme(
              Theme.of(context),
            ).copyWith(p: context.text.body, h1: context.text.title),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
