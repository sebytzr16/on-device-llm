enum MermaidKind { flowchart, sequence, pie }

enum MermaidShape { rect, round, diamond, circle, flag, database }

class MermaidNode {
  final String id;
  final String label;
  final MermaidShape shape;
  final bool actor;
  const MermaidNode(
    this.id,
    this.label, {
    this.shape = MermaidShape.rect,
    this.actor = false,
  });
}

class MermaidEdge {
  final String from, to, label, stroke;
  final bool sequence;
  const MermaidEdge(
    this.from,
    this.to,
    this.stroke, [
    this.label = '',
    this.sequence = false,
  ]);
  bool get dashed => sequence ? stroke.startsWith('--') : stroke.contains('.');
  bool get arrow => stroke != '---';
}

class MermaidGroup {
  final String label;
  final List<String> nodes = [];
  MermaidGroup(this.label);
}

class MermaidEvent {
  final String kind, label;
  final String? from, to;
  final String position;
  const MermaidEvent(
    this.kind,
    this.label, {
    this.from,
    this.to,
    this.position = '',
  });
}

class MermaidSlice {
  final String label;
  final double value;
  const MermaidSlice(this.label, this.value);
}

class MermaidDiagram {
  final MermaidKind kind;
  String direction = 'TD';
  String title = '';
  bool showData = false, autonumber = false;
  int numberStart = 1, numberStep = 1;
  final Map<String, MermaidNode> nodes = {};
  final List<MermaidEdge> edges = [];
  final List<MermaidGroup> groups = [];
  final List<MermaidEvent> events = [];
  final List<MermaidSlice> slices = [];
  MermaidDiagram(this.kind);
}

/// A bounded, offline subset. Unrecognised syntax returns source rendering.
MermaidDiagram? parseMermaid(String source) {
  if (source.length > 32768) return null;
  try {
    return _Parser(source).parse();
  } on FormatException {
    return null;
  }
}

class _Parser {
  final String source;
  late MermaidDiagram diagram;
  final List<MermaidGroup> groups = [];
  int blocks = 0;
  _Parser(this.source);

  Never fail() => throw const FormatException('Unsupported diagram syntax');

  List<String> statements() {
    final result = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    var depth = 0;
    for (var i = 0; i < source.length; i++) {
      final c = source[i];
      if (c == '"') quoted = !quoted;
      if (!quoted &&
          c == '%' &&
          i + 1 < source.length &&
          source[i + 1] == '%') {
        while (i < source.length && source[i] != '\n') {
          i++;
        }
        if (buffer.toString().trim().isNotEmpty) {
          result.add(buffer.toString().trim());
        }
        buffer.clear();
        continue;
      }
      if (!quoted && '[({'.contains(c)) depth++;
      if (!quoted && '])}'.contains(c)) depth--;
      // Flag nodes use an asymmetric delimiter.
      if (!quoted && c == '>' && RegExp(r'[\w]$').hasMatch(buffer.toString())) {
        depth++;
      }
      if (!quoted && (c == '\n' || c == ';' && depth <= 0)) {
        if (buffer.toString().trim().isNotEmpty) {
          result.add(buffer.toString().trim());
        }
        buffer.clear();
      } else {
        buffer.write(c);
      }
    }
    if (quoted) fail();
    if (buffer.toString().trim().isNotEmpty) {
      result.add(buffer.toString().trim());
    }
    return result;
  }

  MermaidDiagram parse() {
    final lines = statements();
    if (lines.isEmpty || lines.length > 500) fail();
    final header = lines.removeAt(0);
    final flow = RegExp(
      r'^(?:flowchart|graph)\s+(TD|TB|BT|LR|RL)\b\s*(.*)$',
    ).firstMatch(header);
    if (flow != null) {
      diagram = MermaidDiagram(MermaidKind.flowchart)..direction = flow[1]!;
      if (flow[2]!.isNotEmpty) lines.insert(0, flow[2]!);
      for (final line in lines) {
        flowLine(line);
      }
      if (groups.isNotEmpty || diagram.nodes.isEmpty) fail();
    } else if (header == 'sequenceDiagram') {
      diagram = MermaidDiagram(MermaidKind.sequence);
      for (final line in lines) {
        sequenceLine(line);
      }
      if (blocks != 0 || diagram.nodes.isEmpty) fail();
    } else if (RegExp(r'^pie(?:\s+showData)?$').hasMatch(header)) {
      diagram = MermaidDiagram(MermaidKind.pie)
        ..showData = header.contains('showData');
      for (final line in lines) {
        if (line.startsWith('title ')) {
          diagram.title = line.substring(6);
          continue;
        }
        final match = RegExp(
          r'^"([^"]+)"\s*:\s*(\d+(?:\.\d+)?)$',
        ).firstMatch(line);
        if (match == null) fail();
        final value = double.parse(match[2]!);
        if (!value.isFinite) fail();
        diagram.slices.add(MermaidSlice(match[1]!, value));
      }
      final total = diagram.slices.fold(0.0, (a, b) => a + b.value);
      if (diagram.slices.isEmpty || !total.isFinite || total <= 0) {
        fail();
      }
    } else {
      fail();
    }
    if (diagram.nodes.length > 160 ||
        diagram.edges.length > 400 ||
        diagram.events.length > 300) {
      fail();
    }
    return diagram;
  }

  String unquote(String value) {
    final v = value.trim();
    return v.startsWith('"') && v.endsWith('"')
        ? v.substring(1, v.length - 1)
        : v;
  }

  void addNode(
    String id, [
    String? label,
    MermaidShape shape = MermaidShape.rect,
    bool actor = false,
  ]) {
    if (label != null || !diagram.nodes.containsKey(id)) {
      diagram.nodes[id] = MermaidNode(
        id,
        label ?? id,
        shape: shape,
        actor: actor,
      );
      if (diagram.nodes.length > 160) fail();
    }
    for (final group in groups) {
      if (!group.nodes.contains(id)) group.nodes.add(id);
    }
  }

  void flowLine(String line) {
    if (RegExp(r'^(classDef|class|style|linkStyle)\b').hasMatch(line)) return;
    if (line.startsWith('subgraph ')) {
      var label = line.substring(9).trim();
      final match = RegExp(r'^\w+\s*\[(.*)\]$').firstMatch(label);
      label = unquote(match?[1] ?? label);
      final group = MermaidGroup(label);
      diagram.groups.add(group);
      groups.add(group);
      return;
    }
    if (line == 'end') {
      if (groups.isEmpty) fail();
      groups.removeLast();
      return;
    }
    var cursor = 0;
    void spaces() {
      while (cursor < line.length && line[cursor].trim().isEmpty) {
        cursor++;
      }
    }

    List<String> nodeSet() {
      final ids = <String>[];
      while (true) {
        spaces();
        final match = RegExp(r'^[\w]+').firstMatch(line.substring(cursor));
        if (match == null) fail();
        final id = match[0]!;
        cursor += id.length;
        spaces();
        String? label;
        var shape = MermaidShape.rect;
        for (final spec in [
          ('((', '))', MermaidShape.circle),
          ('[(', ')]', MermaidShape.database),
          ('[', ']', MermaidShape.rect),
          ('(', ')', MermaidShape.round),
          ('{', '}', MermaidShape.diamond),
          ('>', ']', MermaidShape.flag),
        ]) {
          if (!line.substring(cursor).startsWith(spec.$1)) continue;
          cursor += spec.$1.length;
          final start = cursor;
          var quote = false;
          while (cursor < line.length) {
            if (line[cursor] == '"') quote = !quote;
            if (!quote && line.substring(cursor).startsWith(spec.$2)) break;
            cursor++;
          }
          if (cursor == line.length) fail();
          label = unquote(line.substring(start, cursor));
          cursor += spec.$2.length;
          shape = spec.$3;
          break;
        }
        addNode(id, label, shape);
        ids.add(id);
        spaces();
        if (cursor == line.length || line[cursor] != '&') break;
        cursor++;
      }
      return ids;
    }

    var from = nodeSet();
    while (cursor < line.length) {
      spaces();
      String stroke, label = '';
      final edge = RegExp(
        r'^(-->|---|-\.->|==>)',
      ).firstMatch(line.substring(cursor));
      if (edge != null) {
        stroke = edge[0]!;
        cursor += stroke.length;
        spaces();
        if (cursor < line.length && line[cursor] == '|') {
          final end = line.indexOf('|', cursor + 1);
          if (end < 0) fail();
          label = unquote(line.substring(cursor + 1, end));
          cursor = end + 1;
        }
      } else {
        final labelled = RegExp(
          r'^--\s+(.+?)\s+-->',
        ).firstMatch(line.substring(cursor));
        if (labelled == null) fail();
        stroke = '-->';
        label = unquote(labelled[1]!);
        cursor += labelled[0]!.length;
      }
      final to = nodeSet();
      for (final a in from) {
        for (final b in to) {
          diagram.edges.add(MermaidEdge(a, b, stroke, label));
          if (diagram.edges.length > 400) fail();
        }
      }
      from = to;
    }
  }

  void sequenceLine(String line) {
    final participant = RegExp(
      r'^(participant|actor)\s+(\w+)(?:\s+as\s+(.+))?$',
    ).firstMatch(line);
    if (participant != null) {
      addNode(
        participant[2]!,
        unquote(participant[3] ?? participant[2]!),
        MermaidShape.rect,
        participant[1] == 'actor',
      );
      return;
    }
    final numbering = RegExp(
      r'^autonumber(?:\s+(\d+)(?:\s+(\d+))?)?$',
    ).firstMatch(line);
    if (numbering != null) {
      diagram.autonumber = true;
      diagram.numberStart = int.parse(numbering[1] ?? '1');
      diagram.numberStep = int.parse(numbering[2] ?? '1');
      return;
    }
    final box = RegExp(r'^(loop|alt|opt)\b\s*(.*)$').firstMatch(line);
    if (box != null) {
      blocks++;
      diagram.events.add(MermaidEvent('start', '${box[1]} ${box[2]}'.trim()));
      return;
    }
    if (line == 'end') {
      if (blocks == 0) fail();
      blocks--;
      diagram.events.add(const MermaidEvent('end', ''));
      return;
    }
    if (line == 'else' || line.startsWith('else ')) {
      if (blocks == 0) fail();
      diagram.events.add(MermaidEvent('else', line));
      return;
    }
    final note = RegExp(
      r'^Note\s+(right of|left of|over)\s+(\w+)(?:\s*,\s*(\w+))?\s*:\s*(.*)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (note != null) {
      addNode(note[2]!);
      if (note[3] != null) addNode(note[3]!);
      diagram.events.add(
        MermaidEvent(
          'note',
          note[4]!,
          from: note[2],
          to: note[3],
          position: note[1]!.toLowerCase(),
        ),
      );
      return;
    }
    final message = RegExp(
      r'^(\w+)\s*(-->>|->>|-->|->|-x)\s*(\w+)\s*:\s*(.*)$',
    ).firstMatch(line);
    if (message == null) fail();
    addNode(message[1]!);
    addNode(message[3]!);
    diagram.events.add(
      MermaidEvent(message[2]!, message[4]!, from: message[1], to: message[3]),
    );
  }
}
