import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/desktop/desktop_app.dart';
import 'package:ondevice_llm/desktop/inspector_panel.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/effective_settings_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';

import 'support/desktop_chat_harness.dart';

Finder slider(String label) =>
    find.byWidgetPredicate((w) => w is DesktopSlider && w.label == label);

const resetModel = Key('desktop-inspector-reset');
const resetChat = Key('desktop-inspector-reset-chat');

Future<void> pickScope(WidgetTester tester, String label) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
  await tester.pumpAndSettle();
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('desktop-inspector-scope')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  final t = AppLocalizationsEn();

  testWidgets('structured output validates live and stays in chat overrides', (
    tester,
  ) async {
    final container = await mountDesktopChat(
      tester,
      const DesktopInspectorPanel(),
    );
    final global = container.read(settingsProvider);
    final selector = find.byType(DropdownButtonFormField<ResponseFormat>);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(
      find.text(t.uiAdvancedStructuredOutputPageJSONSchema).last,
    );
    await tester.pumpAndSettle();
    final editor = find.byKey(const Key('desktop-structured-editor'));
    await tester.ensureVisible(editor);
    await tester.enterText(editor, '{broken');
    await tester.pumpAndSettle();
    expect(find.text(t.structuredSchemaInvalid), findsOneWidget);
    await tester.enterText(editor, '[]');
    await tester.pumpAndSettle();
    expect(find.text(t.structuredSchemaObject), findsOneWidget);
    await tester.enterText(editor, '{"type":"object"}');
    await tester.pumpAndSettle();
    expect(find.text(t.structuredSchemaInvalid), findsNothing);
    expect(
      container.read(chatOverridesProvider)['jsonSchema'],
      '{"type":"object"}',
    );
    expect(container.read(settingsProvider), same(global));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.structuredFormatGrammar).last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(editor);
    await tester.enterText(editor, 'root ::= "yes"');
    await tester.pumpAndSettle();
    expect(container.read(chatOverridesProvider)['grammar'], 'root ::= "yes"');
    expect(find.byKey(resetModel), findsNothing);
    await tester.ensureVisible(find.byKey(resetChat));
    await tester.tap(find.byKey(resetChat));
    await tester.pumpAndSettle();
    expect(container.read(chatOverridesProvider), isEmpty);
    expect(find.byKey(const Key('desktop-structured-editor')), findsNothing);
  });

  testWidgets('This chat scope saves instructions to the chat only', (
    tester,
  ) async {
    final container = await mountDesktopChat(
      tester,
      const DesktopInspectorPanel(),
    );
    await pickScope(tester, t.desktopInspectorScopeChat);
    await tester.enterText(find.byType(TextField), 'Be brief.');
    await tester.pumpAndSettle();
    expect(container.read(chatOverridesProvider)['systemPrompt'], 'Be brief.');
    expect(container.read(modelProfilesProvider)['test'], isNull);
    await tester.tap(find.byKey(resetModel));
    await tester.pumpAndSettle();
    expect(container.read(chatOverridesProvider), isEmpty);
  });

  testWidgets('a chat value wins over the model; a model edit clears it', (
    tester,
  ) async {
    final container = await mountDesktopChat(
      tester,
      const DesktopInspectorPanel(),
    );
    final control = slider(t.desktopInspectorTemperature);
    void move(double v) => tester
        .widget<Slider>(
          find.descendant(of: control, matching: find.byType(Slider)),
        )
        .onChanged!(v);
    double temperature() =>
        container.read(effectiveSettingsProvider).effective.temperature;
    await tester.ensureVisible(control);
    expect(tester.widget<DesktopSlider>(control).source, t.desktopSourceMaker);
    move(0.4);
    await tester.pumpAndSettle();
    expect(tester.widget<DesktopSlider>(control).source, t.desktopSourceModel);
    await pickScope(tester, t.desktopInspectorScopeChat);
    move(1.5);
    await tester.pumpAndSettle();
    expect(temperature(), 1.5);
    expect(tester.widget<DesktopSlider>(control).source, t.desktopSourceChat);
    expect(container.read(modelProfilesProvider)['test']?['temperature'], 0.4);
    await pickScope(tester, 'Test Model');
    move(0.8);
    await tester.pumpAndSettle();
    expect(
      container.read(chatOverridesProvider),
      isNot(contains('temperature')),
    );
    expect(temperature(), 0.8);
  });

  testWidgets(
    'instructions save with the model and reset restores inheritance',
    (tester) async {
      final container = await mountDesktopChat(
        tester,
        const DesktopInspectorPanel(),
      );
      final defaults = container.read(effectiveSettingsProvider).effective;
      final global = container.read(settingsProvider);
      await tester.enterText(find.byType(TextField), 'Answer with examples.');
      await tester.pumpAndSettle();
      expect(
        container.read(modelProfilesProvider)['test']?['systemPrompt'],
        'Answer with examples.',
      );
      expect(container.read(chatOverridesProvider), isEmpty);
      expect(
        container.read(effectiveSettingsProvider).effective.systemPrompt,
        'Answer with examples.',
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Answer with examples.',
      );
      expect(container.read(settingsProvider), same(global));
      await tester.tap(find.byKey(resetModel));
      await tester.pumpAndSettle();
      expect(container.read(modelProfilesProvider)['test'] ?? {}, isEmpty);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        defaults.systemPrompt,
      );
      expect(find.byKey(resetModel), findsNothing);
    },
  );

  for (final (chat, scope) in [
    (false, 'with the model'),
    (true, 'to the chat'),
  ]) {
    for (final (label, key, value, display) in [
      (t.desktopInspectorTemperature, 'temperature', 1.25, '1.25'),
      ('Top P', 'topP', 0.6, '0.60'),
      ('Min P', 'minP', 0.12, '0.12'),
      ('Top K', 'topK', 75.0, '75'),
      (t.desktopInspectorRepeatPenalty, 'repetitionPenalty', 1.15, '1.15'),
      (t.desktopInspectorPresencePenalty, 'presencePenalty', 0.5, '0.50'),
      (t.desktopInspectorMaxTokens, 'maxTokens', 2048.0, '2048'),
    ]) {
      testWidgets(
        '$label saves $scope and displays its value; reset restores recommendations',
        (tester) async {
          final container = await mountDesktopChat(
            tester,
            const DesktopInspectorPanel(),
          );
          if (chat) await pickScope(tester, t.desktopInspectorScopeChat);
          Map<String, dynamic> saved() => chat
              ? container.read(chatOverridesProvider)
              : container.read(modelProfilesProvider)['test'] ?? const {};
          final baseline = container
              .read(effectiveSettingsProvider)
              .effective
              .toJson()[key];
          final control = slider(label);
          await tester.ensureVisible(control);
          await tester.pumpAndSettle();
          // Exercise the public Slider callback at an exact division.
          tester
              .widget<Slider>(
                find.descendant(of: control, matching: find.byType(Slider)),
              )
              .onChanged!(value);
          await tester.pumpAndSettle();
          expect(saved()[key], value);
          expect(
            container.read(effectiveSettingsProvider).effective.toJson()[key],
            value,
          );
          expect(
            find.descendant(of: control, matching: find.text(display)),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            find.byKey(resetModel),
            -200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(find.byKey(resetModel));
          await tester.pumpAndSettle();
          expect(saved(), isEmpty);
          expect(
            container.read(effectiveSettingsProvider).effective.toJson()[key],
            baseline,
          );
          expect(tester.widget<DesktopSlider>(control).value, baseline);
        },
      );
    }
  }

  testWidgets(
    'context slider clamps inherited values and gestures respect both bounds',
    (tester) async {
      final container = await mountDesktopChat(
        tester,
        const DesktopInspectorPanel(),
      );
      final control = slider(t.desktopInspectorContext);
      final track = find.descendant(of: control, matching: find.byType(Slider));
      for (final (inherited, clamped) in [(512, 1024.0), (65536, 32768.0)]) {
        container.read(chatOverridesProvider.notifier).state = {
          'contextSize': inherited,
        };
        await tester.pumpAndSettle();
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(track).value, clamped);
      }
      for (final (delta, expected, display) in [
        (-1000.0, 1024, '1K'),
        (1000.0, 32768, '32K'),
      ]) {
        await tester.drag(track, Offset(delta, 0));
        await tester.pumpAndSettle();
        expect(
          container.read(modelProfilesProvider)['test']?['contextSize'],
          expected,
        );
        expect(tester.widget<Slider>(track).value, expected);
        expect(
          find.descendant(of: control, matching: find.text(display)),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Ctrl+I opens and closes the shell inspector; close button closes slot',
    (tester) async {
      await mountDesktopChat(tester, const DesktopShell(), shell: true);
      expect(find.byType(DesktopInspectorPanel), findsNothing);
      Future<void> toggle() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();
      }

      await toggle();
      expect(desktopInspectorOpen.value, isTrue);
      expect(find.byType(DesktopInspectorPanel), findsOneWidget);
      expect(
        tester.getSize(find.byType(DesktopInspectorPanel)).width,
        DesktopInspectorPanel.width,
      );
      await toggle();
      expect(desktopInspectorOpen.value, isFalse);
      expect(find.byType(DesktopInspectorPanel), findsNothing);
      await toggle();
      await tester.tap(
        find.descendant(
          of: find.byType(DesktopInspectorPanel),
          matching: find.byTooltip(t.desktopInspectorClose),
        ),
      );
      await tester.pumpAndSettle();
      expect(desktopInspectorOpen.value, isFalse);
      expect(find.byType(DesktopInspectorPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
