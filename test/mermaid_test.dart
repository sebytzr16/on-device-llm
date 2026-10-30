import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/mermaid/mermaid_parser.dart';
import 'package:ondevice_llm/core/design/mermaid/mermaid_layout.dart';
import 'package:ondevice_llm/core/design/mermaid/mermaid_widget.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/chat_bubble.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/code_block.dart';

Widget host(String source, {bool streaming = false, bool light = false}) =>
    MaterialApp(
      theme: light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ChatBubble(
            streaming: streaming,
            message: ChatMessage(
              id: 'diagram',
              role: ChatRole.assistant,
              content: source,
              timestamp: DateTime.utc(2026),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('layout reuses rebuilds and invalidates layout inputs', (
    tester,
  ) async {
    Widget block({
      String source = 'graph TD\nA --> B',
      double width = 450,
      double scale = 1,
      bool light = false,
    }) => MaterialApp(
      theme: light ? AppTheme.light : AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Center(
          child: SizedBox(
            width: width,
            child: MermaidBlock(source: source, codeBlock: const Text('code')),
          ),
        ),
      ),
    );
    MermaidLayout layout() =>
        (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('mermaid-diagram')),
                    )
                    .painter!
                as MermaidPainter)
            .layout;
    await tester.pumpWidget(block());
    var previous = layout();
    await tester.pumpWidget(block());
    expect(layout(), same(previous));
    for (final widget in [
      block(width: 400),
      block(scale: 1.5),
      block(light: true),
      block(source: 'graph TD\nA --> C'),
    ]) {
      await tester.pumpWidget(widget);
      expect(layout(), isNot(same(previous)));
      previous = layout();
    }
  });
  for (final direction in ['TD', 'TB', 'BT', 'LR', 'RL']) {
    test('flowchart $direction shapes, edges, chains, sets and groups', () {
      final d = parseMermaid('''graph $direction
%% a comment
subgraph outer[Outer group]
A[Rectangle] -->|label| B(Round) --> C{Diamond}
subgraph inner[Inner group]
D((Circle)) --- E>Flag] -.-> F[(Database)]
end
A & B ==> D & E
C -- yes --> F
end
classDef bright fill:red
style A fill:blue
''')!;
      expect(d.direction, direction);
      expect(
        d.nodes.values.map((n) => n.shape).toSet(),
        MermaidShape.values.toSet(),
      );
      expect(d.edges.length, 9);
      expect(
        d.edges.map((e) => e.stroke).toSet(),
        containsAll(['-->', '---', '-.->', '==>']),
      );
      expect(d.edges.map((e) => e.label), containsAll(['label', 'yes']));
      expect(d.groups.first.nodes.length, 6);
      expect(d.groups.last.nodes, ['D', 'E', 'F']);
    });
  }
  test('quoted punctuation, semicolons, comments and node redefinition', () {
    final d = parseMermaid(
      'flowchart LR; A["A; %% ] label"] --> B; B[End] %% comment\nB --> C',
    )!;
    expect(d.nodes['A']!.label, 'A; %% ] label');
    expect(d.nodes['B']!.label, 'End');
    expect(d.edges.length, 2);
  });
  test('sequence aliases, actors, every message, notes and nested frames', () {
    final d = parseMermaid('''sequenceDiagram
participant A as Alice
actor B as Bob
autonumber
loop retry
A->>B: solid
B-->>A: dashed
alt ready
A->B: open
B-->A: dashed open
else failed
A-xB: stopped
opt explain
Note right of A: right
Note left of B: left
Note over A,B: shared
end
end
end
''')!;
    expect(d.nodes['A']!.label, 'Alice');
    expect(d.nodes['B']!.actor, isTrue);
    expect(d.autonumber, isTrue);
    expect(d.events.where((e) => e.kind == 'note').length, 3);
    expect(
      d.events.map((e) => e.kind),
      containsAll(['->>', '-->>', '->', '-->', '-x', 'start', 'else', 'end']),
    );
    final layout = layoutMermaid(d, const TextStyle(fontSize: 14));
    expect(layout.lifelines.length, 2);
    expect(layout.routes.first.edge.label, '1. solid');
    expect(layout.routes.map((r) => r.edge.dashed), [
      false,
      true,
      false,
      true,
      false,
    ]);
    expect(layout.boxes.where((b) => !b.note).length, 4);
  });
  test('pie title, showData and values', () {
    final d = parseMermaid('pie showData\ntitle Pets\n"Dogs": 3\n"Cats": 1.5')!;
    expect(d.kind, MermaidKind.pie);
    expect(d.showData, isTrue);
    expect(d.title, 'Pets');
    expect(d.slices.last.value, 1.5);
  });
  test('autonumber accepts a start and increment; resource limits fall back', () {
    final d = parseMermaid(
      'sequenceDiagram\nautonumber 10 5\nA->>B: one\nB->>A: two',
    )!;
    expect(
      layoutMermaid(
        d,
        const TextStyle(fontSize: 14),
      ).routes.map((r) => r.edge.label),
      ['10. one', '15. two'],
    );
    expect(
      parseMermaid('graph TD\n${List.generate(161, (i) => 'N$i').join("\n")}'),
      isNull,
    );
    expect(
      parseMermaid(
        'graph TD\n${List.generate(21, (i) => 'A$i').join(' & ')} --> ${List.generate(21, (i) => 'B$i').join(' & ')}',
      ),
      isNull,
    );
  });
  test('unsupported and malformed sources fail without throwing', () {
    for (final source in [
      '',
      'gantt\nA',
      'flowchart ZZ\nA',
      'graph TD\nA[broken',
      'graph TD\nA -->',
      'graph TD\nA -->|broken B',
      'graph TD\nend',
      'graph TD\nsubgraph group\nA',
      'sequenceDiagram\nend',
      'sequenceDiagram\nelse fail',
      'sequenceDiagram\nloop retry\nA->B: msg',
      'pie\n"a": 0',
      'pie\n"a": -1',
      'graph TD\nA["unclosed]',
      'a' * 32769,
    ]) {
      expect(
        parseMermaid(source),
        isNull,
        reason: source.substring(0, source.length.clamp(0, 80)),
      );
    }
  });
  for (final direction in ['TD', 'BT', 'LR', 'RL']) {
    test('ten-node $direction layout has no overlapping nodes', () {
      final d = parseMermaid(
        'graph $direction\nA --> B & C & D\nB & C --> E & F\nD --> G\nE & F & G --> H\nH --> I --> J\nJ --> A',
      )!;
      final layout = layoutMermaid(d, const TextStyle(fontSize: 14));
      final nodes = layout.nodes.values.toList();
      expect(nodes.length, 10);
      for (var i = 0; i < nodes.length; i++) {
        expect((Offset.zero & layout.size).contains(nodes[i].topLeft), isTrue);
        expect(
          (Offset.zero & layout.size).contains(nodes[i].bottomRight),
          isTrue,
        );
        for (var j = i + 1; j < nodes.length; j++) {
          expect(nodes[i].overlaps(nodes[j]), isFalse);
        }
      }
      expect(layout.routes.every((r) => r.points.length >= 2), isTrue);
    });
  }
  testWidgets('shared answer renders diagram, toggles source and copies', (
    tester,
  ) async {
    const source = 'flowchart TD\nA[Start] --> B[End]';
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(host('```mermaid\n$source\n```'));
    expect(find.byKey(const ValueKey('mermaid-diagram')), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('Copy source'));
    expect(copied, source);
    await tester.tap(find.text('Code'));
    await tester.pump();
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.byKey(const ValueKey('mermaid-diagram')), findsNothing);
    await tester.tap(find.text('Diagram'));
    await tester.pump();
    expect(find.byKey(const ValueKey('mermaid-diagram')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('streaming open fence stays code until closed', (tester) async {
    const source = '~~~mermaid\nflowchart LR\nA --> B\n';
    await tester.pumpWidget(host(source, streaming: true));
    expect(find.byType(MermaidBlock), findsNothing);
    expect(find.byType(CodeBlock), findsOneWidget);
    await tester.pumpWidget(
      host('$source~~~\n\n```mermaid\nflowchart TD\nC --> D', streaming: true),
    );
    expect(find.byKey(const ValueKey('mermaid-diagram')), findsOneWidget);
    expect(find.byType(CodeBlock), findsOneWidget);
    await tester.pumpWidget(host('$source~~~', streaming: true));
    expect(find.byKey(const ValueKey('mermaid-diagram')), findsOneWidget);
  });
  testWidgets('unsupported source has normal code and caption', (tester) async {
    await tester.pumpWidget(host('```mermaid\ngantt\nsection Work\n```'));
    expect(find.byType(CodeBlock), findsOneWidget);
    expect(find.text('Diagram type not supported'), findsOneWidget);
  });
  testWidgets('sequence and pie paint in both themes at phone width', (
    tester,
  ) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final light in [false, true]) {
      for (final source in [
        'sequenceDiagram\nactor A as User\nparticipant B as App\nloop retry\nA->>B: hello\nB-->>A: response\nNote over A,B: note\nend',
        'pie showData\ntitle Pets\n"Dogs": 3\n"Cats": 2',
      ]) {
        await tester.pumpWidget(host('```mermaid\n$source\n```', light: light));
        expect(find.byKey(const ValueKey('mermaid-diagram')), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    }
  });
}
