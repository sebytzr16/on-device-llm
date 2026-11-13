import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// A safe wrapper around [MarkdownBody] that never loads network, file, or data
/// images. Instead, it displays the alt text in a small muted [Text] widget,
/// or nothing if alt is empty. This prevents accidental data exfiltration or
/// unwanted network requests when rendering untrusted markdown content.
class SafeMarkdownBody extends StatelessWidget {
  /// Creates a [SafeMarkdownBody] with the given parameters.
  ///
  /// All parameters are forwarded to [MarkdownBody] except [imageBuilder],
  /// which is fixed to a safe implementation that never loads images.
  const SafeMarkdownBody({
    super.key,
    required this.data,
    this.selectable = false,
    this.styleSheet,
    this.inlineSyntaxes,
    this.builders,
    this.extensionSet,
    this.onTapLink,
    this.softLineBreak = false,
    this.shrinkWrap = true,
    this.listItemCrossAxisAlignment =
        MarkdownListItemCrossAxisAlignment.baseline,
  });

  /// The markdown data to render.
  final String data;

  /// Whether the text should be selectable.
  final bool selectable;

  /// The style sheet to use for rendering.
  final MarkdownStyleSheet? styleSheet;

  /// Custom inline syntaxes.
  final List<md.InlineSyntax>? inlineSyntaxes;

  /// Custom element builders.
  final Map<String, MarkdownElementBuilder>? builders;

  /// The extension set to use.
  final md.ExtensionSet? extensionSet;

  /// Callback when a link is tapped.
  final MarkdownTapLinkCallback? onTapLink;

  /// Whether to treat single newlines as hard breaks.
  final bool softLineBreak;

  /// If [shrinkWrap] is `true`, [MarkdownBody] will take the minimum height
  /// that wraps its content. Otherwise, [MarkdownBody] will expand to the
  /// maximum allowed height.
  final bool shrinkWrap;

  /// Controls the cross axis alignment for the bullet and list item content
  /// in lists.
  final MarkdownListItemCrossAxisAlignment listItemCrossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: styleSheet,
      inlineSyntaxes: inlineSyntaxes,
      builders: builders ?? const <String, MarkdownElementBuilder>{},
      extensionSet: extensionSet,
      onTapLink: onTapLink,
      softLineBreak: softLineBreak,
      shrinkWrap: shrinkWrap,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      // Never load network, file, or data images. Show alt text instead,
      // or nothing if alt is empty.
      imageBuilder: (uri, title, alt) {
        if (alt == null || alt.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final textStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(alt, style: textStyle, textAlign: TextAlign.center),
        );
      },
    );
  }
}

/// A safe wrapper around [Markdown] that never loads network, file, or data
/// images. Instead, it displays the alt text in a small muted [Text] widget,
/// or nothing if alt is empty.
class SafeMarkdown extends StatelessWidget {
  /// Creates a [SafeMarkdown] with the given parameters.
  ///
  /// All parameters are forwarded to [Markdown] except [imageBuilder],
  /// which is fixed to a safe implementation that never loads images.
  const SafeMarkdown({
    super.key,
    required this.data,
    this.selectable = false,
    this.styleSheet,
    this.inlineSyntaxes,
    this.builders,
    this.extensionSet,
    this.onTapLink,
    this.softLineBreak = false,
    this.padding = const EdgeInsets.all(16.0),
    this.controller,
    this.physics,
    this.shrinkWrap = false,
    this.noScroll = false,
    this.listItemCrossAxisAlignment =
        MarkdownListItemCrossAxisAlignment.baseline,
  });

  /// The markdown data to render.
  final String data;

  /// Whether the text should be selectable.
  final bool selectable;

  /// The style sheet to use for rendering.
  final MarkdownStyleSheet? styleSheet;

  /// Custom inline syntaxes.
  final List<md.InlineSyntax>? inlineSyntaxes;

  /// Custom element builders.
  final Map<String, MarkdownElementBuilder>? builders;

  /// The extension set to use.
  final md.ExtensionSet? extensionSet;

  /// Callback when a link is tapped.
  final MarkdownTapLinkCallback? onTapLink;

  /// Whether to treat single newlines as hard breaks.
  final bool softLineBreak;

  /// The amount of space by which to inset the children.
  final EdgeInsetsGeometry padding;

  /// An object that can be used to control the position to which this scroll
  /// view is scrolled.
  final ScrollController? controller;

  /// How the scroll view should respond to user input.
  final ScrollPhysics? physics;

  /// Whether the extent of the scroll view in the scroll direction should be
  /// determined by the contents being viewed.
  final bool shrinkWrap;

  /// If true, the markdown is rendered in a non-scrolling [Column] instead of
  /// a scrolling [ListView]. Use this when the widget is already inside a
  /// scrolling parent.
  final bool noScroll;

  /// Controls the cross axis alignment for the bullet and list item content
  /// in lists.
  final MarkdownListItemCrossAxisAlignment listItemCrossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Markdown(
      data: data,
      selectable: selectable,
      styleSheet: styleSheet,
      inlineSyntaxes: inlineSyntaxes,
      builders: builders ?? const <String, MarkdownElementBuilder>{},
      extensionSet: extensionSet,
      onTapLink: onTapLink,
      softLineBreak: softLineBreak,
      padding: padding.resolve(Directionality.of(context)),
      controller: controller,
      physics: physics,
      shrinkWrap: shrinkWrap,
      noScroll: noScroll,
      listItemCrossAxisAlignment: listItemCrossAxisAlignment,
      // Never load network, file, or data images. Show alt text instead,
      // or nothing if alt is empty.
      imageBuilder: (uri, title, alt) {
        if (alt == null || alt.isEmpty) return const SizedBox.shrink();
        final theme = Theme.of(context);
        final textStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontStyle: FontStyle.italic,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(alt, style: textStyle, textAlign: TextAlign.center),
        );
      },
    );
  }
}
