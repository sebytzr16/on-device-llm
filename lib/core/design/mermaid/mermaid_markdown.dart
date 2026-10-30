import 'package:markdown/markdown.dart' as md;

/// Preserve the fence state that Markdown normally discards.
class MermaidFenceSyntax extends md.FencedCodeBlockSyntax {
  const MermaidFenceSyntax();

  @override
  md.Node parse(md.BlockParser parser) {
    final opening = RegExp(
      r'^ {0,3}(`{3,}|~{3,})mermaid(?:\s.*)?$',
    ).firstMatch(parser.current.content);
    var closed = false;
    if (opening != null) {
      final marker = opening[1]!;
      final closing = RegExp('^ {0,3}${marker[0]}{${marker.length},}\\s*\$');
      for (var i = 1; parser.peek(i) != null; i++) {
        if (closing.hasMatch(parser.peek(i)!.content)) {
          closed = true;
          break;
        }
      }
    }
    final node = super.parse(parser) as md.Element;
    if (opening != null) node.attributes['mermaid-closed'] = '$closed';
    return node;
  }
}
