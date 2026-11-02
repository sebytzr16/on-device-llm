import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/desktop/chat_pane.dart';
import 'package:ondevice_llm/desktop/inspector_panel.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_sampling_variants_provider.dart';

import 'support/desktop_chat_harness.dart';

void main() {
  final t = AppLocalizationsEn();
  final menu = find.byKey(const Key('desktop-model-preset-menu'));
  final pill = find.byKey(const Key('desktop-model-preset-pill'));

  // The inspector builds lazily: scroll back up to a control left behind.
  Future<void> reveal(WidgetTester tester, Finder control) async {
    if (control.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        control,
        -200,
        scrollable: find
            .descendant(
              of: find.byType(DesktopInspectorPanel),
              matching: find.byType(Scrollable),
            )
            .first,
      );
    }
    await tester.ensureVisible(control);
  }

  Future<void> pick(WidgetTester tester, Finder control, String label) async {
    await reveal(tester, control);
    await tester.tap(control);
    await tester.pumpAndSettle();
    await tester.tap(
      find
          .ancestor(
            of: find.text(label).last,
            matching: find.byWidgetPredicate((w) => w is PopupMenuEntry),
          )
          .last,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('inspector saves, switches and updates a modified variant', (
    tester,
  ) async {
    final c = await mountDesktopChat(tester, const DesktopInspectorPanel());
    final temp = find.byWidgetPredicate(
      (w) => w is DesktopSlider && w.label == t.desktopInspectorTemperature,
    );
    void move(double value) =>
        tester.widget<DesktopSlider>(temp).onChanged(value);
    await tester.ensureVisible(temp);
    move(0.2);
    await tester.pumpAndSettle();
    await pick(tester, menu, t.desktopModelPresetSaveAs);
    await tester.enterText(
      find.byKey(const Key('desktop-model-preset-name')),
      'Focused',
    );
    await tester.tap(find.text(t.save).last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.read(modelSamplingVariantsProvider)['test']!.active, 'Focused');
    await tester.ensureVisible(temp);
    move(1.0);
    await tester.pumpAndSettle();
    await reveal(tester, menu);
    expect(
      find.byKey(const Key('desktop-model-preset-modified')),
      findsOneWidget,
    );
    await pick(tester, menu, t.desktopModelPresetSaveAs);
    await tester.enterText(
      find.byKey(const Key('desktop-model-preset-name')),
      'Playful',
    );
    await tester.tap(find.text(t.save).last);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await pick(tester, menu, 'Focused');
    await tester.ensureVisible(temp);
    expect(tester.widget<DesktopSlider>(temp).value, 0.2);
    expect(tester.widget<DesktopSlider>(temp).source, t.desktopSourceModel);
    move(0.3);
    await tester.pumpAndSettle();
    await pick(tester, menu, t.desktopModelPresetUpdate);
    expect(
      c
          .read(modelSamplingVariantsProvider)['test']!
          .selected!
          .values['temperature'],
      0.3,
    );
    expect(
      find.byKey(const Key('desktop-model-preset-modified')),
      findsNothing,
    );
    await pick(tester, menu, 'Playful');
    await tester.ensureVisible(temp);
    expect(tester.widget<DesktopSlider>(temp).value, 1.0);
    await pick(tester, menu, t.desktopModelPresetDefault);
    expect(c.read(modelProfilesProvider)['test']?['temperature'], null);
    await tester.ensureVisible(temp);
    expect(tester.widget<DesktopSlider>(temp).value, 0.65);
  });

  testWidgets('save suggestions are opt-in and apply their sampling values', (
    tester,
  ) async {
    final c = await mountDesktopChat(tester, const DesktopInspectorPanel());
    expect(c.read(modelSamplingVariantsProvider)['test'], null);
    await pick(tester, menu, t.desktopModelPresetSaveAs);
    await tester.tap(find.text(t.desktopModelPresetCreative));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.read(modelProfilesProvider)['test']!['temperature'], 1.0);
    expect(c.read(modelProfilesProvider)['test']!['topP'], 0.95);
    expect(c.read(modelSamplingVariantsProvider)['test']!.variants.length, 1);
  });

  testWidgets('manage renames, overwrites and deletes variants', (
    tester,
  ) async {
    final c = await mountDesktopChat(tester, const DesktopInspectorPanel());
    final variants = c.read(modelSamplingVariantsProvider.notifier);
    await variants.save('test', 'Focused', values: {'temperature': 0.2});
    await tester.pumpAndSettle();
    await pick(tester, menu, t.desktopModelPresetManage);
    await tester.tap(find.byTooltip(t.desktopModelPresetRename));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('desktop-model-preset-name')),
      'Renamed',
    );
    await tester.tap(find.text(t.save));
    await tester.pumpAndSettle();
    expect(variants.of('test').active, 'Renamed');
    await c
        .read(modelProfilesProvider.notifier)
        .setKey('test', 'temperature', 0.4);
    await tester.tap(find.byTooltip(t.desktopModelPresetUpdate));
    await tester.pumpAndSettle();
    expect(variants.of('test').selected!.values['temperature'], 0.4);
    await tester.tap(find.byTooltip(t.desktopModelPresetDelete));
    await tester.pumpAndSettle();
    expect(variants.of('test').variants, isEmpty);
    expect(find.text(t.desktopModelPresetEmpty), findsOneWidget);
    await tester.tap(find.text(t.desktopInspectorClose).last);
    await tester.pumpAndSettle();
  });

  testWidgets('composer pill appears only for variants of the loaded model', (
    tester,
  ) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    final c = await mountDesktopChat(
      tester,
      DesktopChatPane(composerFocus: focus),
    );
    expect(pill, findsNothing);
    final v = c.read(modelSamplingVariantsProvider.notifier);
    await v.save('other', 'Other', values: {'temperature': 1.0});
    await tester.pumpAndSettle();
    expect(pill, findsNothing);
    await v.save('test', 'Focused', values: {'temperature': 0.2});
    await tester.pumpAndSettle();
    expect(pill, findsOneWidget);
    await pick(tester, pill, 'Focused');
    expect(c.read(modelProfilesProvider)['test']!['temperature'], 0.2);
    await v.delete('test', 'Focused');
    await tester.pumpAndSettle();
    expect(pill, findsNothing);
  });
}
