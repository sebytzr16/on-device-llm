import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;

/// Dollar math must contain mathematical syntax, so ordinary prices remain
/// text. Markdown's code and escape syntaxes run before this syntax.
class MathSyntax extends md.InlineSyntax {
  MathSyntax()
    : super(r'\$\$([^$]+)\$\$|\$([^$\n]+)\$|\\\((.+?)\\\)|\\\[([\s\S]+?)\\\]');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final tex = match[1] ?? match[2] ?? match[3] ?? match[4]!;
    if (tex.length > 2048 ||
        (match[2] != null &&
            !tex.contains(RegExp(r'[\\=^_+*/<>-]')) &&
            !RegExp(r'^[a-zA-Z]$').hasMatch(tex.trim()))) {
      parser.addNode(md.Text(match[0]!));
      return true;
    }
    final node = md.Element.text('math', tex);
    node.attributes['display'] = '${match[1] != null || match[4] != null}';
    parser.addNode(node);
    return true;
  }
}

class MathBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final tex = element.textContent;
    return Builder(
      builder: (context) {
        final style = preferredStyle ?? DefaultTextStyle.of(context).style;
        // Both parsing and layout errors fall back to readable source text.
        return Semantics(
          label: tex,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Math.tex(
              tex,
              mathStyle: element.attributes['display'] == 'true'
                  ? MathStyle.display
                  : MathStyle.text,
              textStyle: style,
              onErrorFallback: (_) => Text(tex, style: style),
            ),
          ),
        );
      },
    );
  }
}
