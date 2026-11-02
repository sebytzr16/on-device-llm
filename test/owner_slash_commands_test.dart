import 'package:ondevice_llm/desktop/chat_pane.dart';
import 'package:ondevice_llm/features/chat/presentation/providers/chat_provider.dart';
import 'support/desktop_chat_harness.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/features/shortcuts/presentation/slash_command_composer.dart';
import 'package:ondevice_llm/features/shortcuts/prompt_shortcuts_provider.dart';
import 'package:ondevice_llm/features/shortcuts/domain/prompt_shortcut.dart';
import 'package:ondevice_llm/features/shortcuts/domain/context_compactor.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/text_engine.dart';
import 'package:ondevice_llm/features/tools/domain/tool_spec.dart';

class _Engine extends TextEngine {
  final seen = <String>[];
  @override
  Map<String, dynamic> get metrics => {};
  @override
  void cancel() {}
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) async => {'fits': (messages.last['content'] as String).length <= 1000};
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) async* {
    seen.add(messages.last['content'] as String);
    yield 'A concise summary.';
  }
}

void main() {
  testWidgets(
    'slash menu filters and supports arrows Enter Tab and Escape plus saved prompts',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(promptShortcutsProvider.notifier).ready;
      await container
          .read(promptShortcutsProvider.notifier)
          .put(
            const PromptShortcut(
              name: 'custom',
              description: 'Saved',
              template: 'Prompt {input}',
            ),
          );
      var submissions = 0;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SlashCommandComposer(
                controller: controller,
                onSubmit: () => submissions++,
                child: TextField(controller: controller),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      expect(find.byKey(const Key('shortcut-compact')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(controller.text, '/clear');
      expect(submissions, 1);
      await tester.enterText(find.byType(TextField), '/exp');
      await tester.pump();
      expect(find.byKey(const Key('shortcut-explain')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.text, '/export');
      expect(submissions, 2);
      await tester.enterText(find.byType(TextField), '/cus');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.text, '/custom ');
      await tester.enterText(find.byType(TextField), '/');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const Key('shortcut-suggestions')), findsNothing);
      expect(controller.text, '/');
    },
  );
  testWidgets('desktop Enter completes a slash before sending', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final container = await mountDesktopChat(
      tester,
      DesktopChatPane(composerFocus: focus),
    );
    final field = find.descendant(
      of: find.byType(DesktopChatPane),
      matching: find.byType(TextField),
    );
    await tester.enterText(field, '/expl');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, '/explain ');
    expect(
      (container.read(chatProvider.notifier) as DesktopTestChat).sent,
      isEmpty,
    );
  });
  test(
    'compaction covers every source chunk and recursively summarizes to fit',
    () async {
      final engine = _Engine();
      final source = List.generate(4000, (i) => '${i % 10}').join();
      final result = await const ContextCompactor().summarize(
        engine: engine,
        settings: const InferenceSettings(),
        source: source,
        instruction: 'Summarize',
        fallbackTemplate: 'chatml',
        fitError: 'Too large',
      );
      expect(result, 'A concise summary.');
      expect(engine.seen.take(4).join(), source);
      expect(engine.seen, hasLength(5));
    },
  );
}
