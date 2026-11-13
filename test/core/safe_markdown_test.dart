import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/widgets/safe_markdown.dart';

void main() {
  test('S01 report, findings and preview keep the safe renderer', () {
    const surfaces = {
      'lib/features/goals/presentation/goal_blocks.dart': 'SafeMarkdownBody(',
      'lib/features/goals/presentation/goal_tiles.dart': 'SafeMarkdownBody(',
      'lib/features/chat/presentation/screens/chat_screen_actions.dart':
          'SafeMarkdown(',
    };
    for (final entry in surfaces.entries) {
      final source = File(entry.key).readAsStringSync();
      expect(source, contains(entry.value), reason: entry.key);
      expect(
        RegExp(r'(?<![A-Za-z])Markdown(?:Body)?\(').hasMatch(source),
        isFalse,
        reason: '${entry.key} must not use default image loaders',
      );
    }
  });

  for (final body in [true, false]) {
    testWidgets('S01 loopback image is inert without web permission ($body)', (
      tester,
    ) async {
      const data = '![tracking](http://127.0.0.1:8080/private)';
      // The renderer has no permission dependency and never creates a loader,
      // including when no web-enabled settings/provider scope exists.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: body
                ? const SafeMarkdownBody(data: data)
                : const SafeMarkdown(data: data),
          ),
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.text('tracking'), findsOneWidget);
    });
  }

  group('SafeMarkdownBody', () {
    testWidgets('does not build Image widget for http URL', (tester) async {
      const markdown = '![Alt text](http://example.com/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdownBody(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Alt text'), findsOneWidget);
    });

    testWidgets('does not build Image widget for https URL', (tester) async {
      const markdown = '![Alt text](https://example.com/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdownBody(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Alt text'), findsOneWidget);
    });

    testWidgets('does not build Image widget for file URL', (tester) async {
      const markdown = '![Alt text](file:///path/to/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdownBody(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Alt text'), findsOneWidget);
    });

    testWidgets('does not build Image widget for data URL', (tester) async {
      const markdown = '![Alt text](data:image/png;base64,abc123)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdownBody(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Alt text'), findsOneWidget);
    });

    testWidgets('shows nothing when alt text is empty', (tester) async {
      const markdown = '![](http://example.com/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdownBody(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('[Image omitted]'), findsNothing);
    });

    testWidgets('shows nothing when alt text is missing', (tester) async {
      const markdown = '![](http://example.com/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdownBody(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('[Image omitted]'), findsNothing);
    });

    testWidgets('renders text content normally', (tester) async {
      const markdown = '# Hello\n\nThis is **bold** text.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdownBody(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('This is bold text.'), findsOneWidget);
    });
  });

  group('SafeMarkdown', () {
    testWidgets('does not build Image widget for http URL', (tester) async {
      const markdown = '![Alt text](http://example.com/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdown(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Alt text'), findsOneWidget);
    });

    testWidgets('does not build Image widget for https URL', (tester) async {
      const markdown = '![Alt text](https://example.com/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdown(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Alt text'), findsOneWidget);
    });

    testWidgets('does not build Image widget for file URL', (tester) async {
      const markdown = '![Alt text](file:///path/to/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdown(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Alt text'), findsOneWidget);
    });

    testWidgets('does not build Image widget for data URL', (tester) async {
      const markdown = '![Alt text](data:image/png;base64,abc123)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdown(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Alt text'), findsOneWidget);
    });

    testWidgets('shows nothing when alt text is empty', (tester) async {
      const markdown = '![](http://example.com/image.png)';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdown(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('[Image omitted]'), findsNothing);
    });

    testWidgets('renders text content normally', (tester) async {
      const markdown = '# Hello\n\nThis is **bold** text.';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SafeMarkdown(data: markdown)),
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('This is bold text.'), findsOneWidget);
    });
  });
}
