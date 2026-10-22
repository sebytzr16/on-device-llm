import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/goals/goal_specialization.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_texts.dart';
import 'package:ondevice_llm/features/schedule/schedule_page.dart';
import 'package:ondevice_llm/l10n/app_localizations_fr.dart';
import 'package:ondevice_llm/l10n/app_localizations_es.dart';

void main() {
  test('every goal kind has English text equal to its model-facing name', () {
    final en = AppLocalizationsEn();
    for (final k in GoalSpecialization.values) {
      expect(k.labelIn(en), k.label);
      expect(k.descriptionIn(en), k.description);
      expect(k.criteriaIn(en), k.criteriaHint);
    }
  });

  test('French plurals and placeholders', () {
    final fr = AppLocalizationsFr();
    expect(fr.goalStepsOf(1, 1), '1 sur 1 étape');
    expect(fr.goalStepsOf(2, 5), '2 sur 5 étapes');
    expect(fr.goalSources(1), '1 source');
    expect(fr.goalSources(3), '3 sources');
    expect(fr.batterySaverOn(20), contains('20 %'));
    expect(
      fr.shortcutPromptHelp('{input}'),
      startsWith('{input} est remplacé'),
    );
    expect(GoalSpecialization.math.labelIn(fr), 'Maths');
  });

  test('Spanish plurals and key feature strings', () {
    final es = AppLocalizationsEs();
    expect(es.goalStepsOf(1, 1), '1 de 1 paso');
    expect(es.goalStepsOf(2, 5), '2 de 5 pasos');
    expect(es.goalSources(2), '2 fuentes');
    expect(es.saveToKnowledge, 'Guardar en la biblioteca');
    expect(
      es.readerSummarizePrompt('https://example.com'),
      contains('https://example.com'),
    );
  });

  test('tool identifiers stay literal in both translated settings pages', () {
    for (final locale in [AppLocalizationsFr(), AppLocalizationsEs()]) {
      expect(
        locale.uiToolsQuickPanelSearchWebReadUrlFindIn,
        'search_web · read_url · find_in_page',
      );
      expect(locale.uiAdvancedToolsPageSearchDocuments, 'search_documents');
    }
    expect(AppLocalizationsEs().shortcutsRowHint, contains('/summarize'));
    expect(
      AppLocalizationsEs().uiAdvancedSamplingPageDRYMultiplier,
      contains('DRY'),
    );
  });

  testWidgets('the scheduled prompts page speaks Spanish', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SchedulePage(
          load: () async => const [],
          save: (_) async {},
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Avisos programados'), findsOneWidget);
  });

  testWidgets('the scheduled prompts page speaks French', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        locale: const Locale('fr'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SchedulePage(
          load: () async => const [],
          save: (_) async {},
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Invites programmées'), findsOneWidget);
    expect(find.textContaining('Aucune pour l'), findsOneWidget);
  });
}
