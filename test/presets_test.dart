import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/motion/motion.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/presets/domain/preset.dart';
import 'package:ondevice_llm/features/presets/presentation/preset_sheet.dart';
import 'package:ondevice_llm/features/presets/presentation/providers/presets_provider.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'editing a preset keeps its overrides and an off-menu temperature '
    '(P1-28, P2-40)',
    (tester) async {
      const own = Preset(
        id: 'mine',
        name: 'Mine',
        emoji: '🧪',
        systemPrompt: 'Translate.',
        temperature: 0.2,
        overrides: {'topK': 20},
      );
      Preset? saved;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, page) =>
              MotionScope(choice: MotionChoice.off, child: page!),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async =>
                    saved = await showPresetEditor(context, existing: own),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('0.2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('preset-save')));
      await tester.pumpAndSettle();
      expect(saved!.id, 'mine');
      expect(saved!.temperature, 0.2);
      expect(saved!.overrides, {'topK': 20});
    },
  );

  test('a duplicate keeps the overrides (P1-28)', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(presetsProvider.notifier);
    await n.ready;
    final copy = await n.duplicate(
      Preset.builtIns.first.copyWith(overrides: {'topK': 20}),
    );
    expect(copy.overrides, {'topK': 20});
  });

  test('a preset overrides only what it sets and round-trips JSON', () {
    const s = InferenceSettings(temperature: 0.7, thinkingModeEnabled: true);
    final concise = Preset.builtIns.firstWhere((p) => p.id == 'concise');
    final applied = concise.apply(s);
    expect(applied.temperature, 0.3);
    expect(applied.thinkingModeEnabled, false);
    expect(applied.webMode, s.webMode, reason: 'not overridden');
    expect(Preset.general.apply(s).toJson(), s.toJson());
    const own = Preset(
      id: 'x',
      name: 'Mine',
      emoji: '🧪',
      systemPrompt: 'Be brief.',
      temperature: 0.1,
      webMode: WebMode.always,
    );
    final back = Preset.fromJson(own.toJson());
    expect(back.toJson(), own.toJson());
    expect(back.thinking, isNull);
  });

  test(
    'user presets persist and the active choice survives a reload',
    () async {
      SharedPreferences.setMockInitialValues({});
      var container = ProviderContainer();
      var n = container.read(presetsProvider.notifier);
      await n.ready;
      expect(
        container.read(presetsProvider).presets.length,
        Preset.builtIns.length,
      );
      final created = await n.create(
        const Preset(
          id: '',
          name: 'Mine',
          emoji: '',
          systemPrompt: 'Be brief.',
        ),
      );
      expect(created.emoji, '✨');
      expect(container.read(presetsProvider).activeId, created.id);
      await n.update(created.copyWith(systemPrompt: 'Be very brief.'));
      container.dispose();

      container = ProviderContainer();
      n = container.read(presetsProvider.notifier);
      await n.ready;
      final state = container.read(presetsProvider);
      expect(state.active.systemPrompt, 'Be very brief.');
      // Built-ins cannot be deleted; deleting the active one falls back.
      await n.remove('concise');
      expect(state.presets.any((p) => p.id == 'concise'), true);
      await n.remove(created.id);
      expect(container.read(presetsProvider).activeId, 'general');
      container.dispose();
    },
  );
}
