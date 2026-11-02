import 'package:flutter/material.dart';

/// Reuses finished paragraphs while only the open tail changes. Constructs
/// whose meaning can depend on later lines stay together until completion.
class StreamingMarkdown extends StatefulWidget {
  final String data;
  final bool streaming;
  final double blockSpacing;
  final Widget Function(String) builder;

  const StreamingMarkdown({
    super.key,
    required this.data,
    required this.streaming,
    this.blockSpacing = 0,
    required this.builder,
  });

  @override
  State<StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<StreamingMarkdown> {
  final _finished = <Widget>[];
  String _prefix = '';

  int _blockEnd(String tail) {
    String? fence;
    var fenceLength = 0;
    var complex = false;
    var html = false;
    var math = false;
    var offset = 0;
    final lines = tail.split('\n');
    for (var i = 0; i < lines.length - 1; i++) {
      final line = lines[i];
      offset += line.length + 1;
      final marker = RegExp(r'^ {0,3}(`{3,}|~{3,})(.*)$').firstMatch(line);
      if (marker != null) {
        final run = marker[1]!;
        if (fence == null) {
          fence = run[0];
          fenceLength = run.length;
        } else if (run[0] == fence &&
            run.length >= fenceLength &&
            marker[2]!.trim().isEmpty) {
          fence = null;
        }
        continue;
      }
      if (fence != null) continue;
      if (RegExp(r'\$\$').allMatches(line).length.isOdd) math = !math;
      if (RegExp(r'^\s*<').hasMatch(line)) html = true;
      if (RegExp(r'^(\s*([-*+] |\d+[.)] |>)| {4}|\t)|\|').hasMatch(line)) {
        complex = true;
      }
      if (line.trim().isNotEmpty ||
          math ||
          html ||
          tail.substring(0, offset).trim().isEmpty) {
        continue;
      }
      // A top-level heading terminates lists, quotes and tables. Otherwise
      // retain those constructs so blank lines inside them keep their meaning.
      if (!complex || RegExp(r'^#{1,6}\s+\S').hasMatch(lines[i + 1])) {
        return offset;
      }
    }
    return 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _finished.clear();
    _prefix = '';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    // Reference definitions can retroactively change earlier paragraphs.
    // Brackets inside code have no such effect.
    final referenceText = data.contains('[')
        ? data.replaceAll(
            RegExp(r'```[\s\S]*?(?:```|$)|~~~[\s\S]*?(?:~~~|$)|`[^`]*`'),
            '',
          )
        : '';
    if (!widget.streaming ||
        RegExp(
          r'^ {0,3}\[[^\]\n]+\]:',
          multiLine: true,
        ).hasMatch(referenceText)) {
      _finished.clear();
      _prefix = '';
      return widget.builder(data);
    }
    if (!data.startsWith(_prefix)) {
      _finished.clear();
      _prefix = '';
    }
    var tail = data.substring(_prefix.length);
    while (true) {
      final end = _blockEnd(tail);
      if (end == 0) break;
      final block = tail.substring(0, end);
      _finished.add(widget.builder(block));
      _prefix += block;
      tail = tail.substring(block.length);
    }
    return Column(
      spacing: widget.blockSpacing,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [..._finished, if (tail.isNotEmpty) widget.builder(tail)],
    );
  }
}
