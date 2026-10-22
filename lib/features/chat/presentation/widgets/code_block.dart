import '../../../../core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/motion/motion.dart';

/// Replaces flutter_markdown's fenced-code rendering with a raised mono
/// panel carrying the language tag and a copy button.
///
/// The element is typed `dynamic` on purpose: `package:markdown` is only a
/// transitive dependency and importing it directly trips the analyzer.
class CodeBlockBuilder extends MarkdownElementBuilder {
  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    dynamic element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    String? lang;
    for (final dynamic child in (element.children as List?) ?? const []) {
      // Text nodes carry no attributes; only the inner <code> element does.
      try {
        lang = (child.attributes['class'] as String?)?.replaceFirst(
          'language-',
          '',
        );
      } catch (_) {}
      if (lang != null) break;
    }
    return CodeBlock(
      code: (element.textContent as String).replaceFirst(RegExp(r'\n$'), ''),
      language: lang?.isEmpty == true ? null : lang,
    );
  }
}

class CodeBlock extends StatelessWidget {
  final String code;
  final String? language;
  const CodeBlock({super.key, required this.code, this.language});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppDesign.sm),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: c.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.only(left: AppDesign.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    language ?? 'code',
                    style: context.text.mono.copyWith(color: c.textFaint),
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.uiCodeBlockCopyCode,
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy_outlined),
                  onPressed: () {
                    AppHaptics.tick();
                    Clipboard.setData(ClipboardData(text: code));
                    showIslandToast(
                      context,
                      context.l10n.uiCodeBlockCodeCopied,
                      tone: IslandTone.done,
                    );
                  },
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(AppDesign.md),
            child: SelectableText(
              code,
              style: context.text.mono.copyWith(color: c.text),
            ),
          ),
        ],
      ),
    );
  }
}
