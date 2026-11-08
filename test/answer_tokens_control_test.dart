import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/presentation/widgets/answer_tokens_control.dart';
import 'package:ondevice_llm/l10n/app_localizations_en.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';

final _en = AppLocalizationsEn();

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  test('parse accepts grouped whole numbers within the schema range', () {
    expect(AnswerTokensControl.parse('128,000'), 128000);
    expect(AnswerTokensControl.parse('128 000'), 128000);
    expect(AnswerTokensControl.parse(' 1 '), 1);
    for (final invalid in ['0', '-5', '1.5', 'abc', '1048577', '12,34']) {
      expect(AnswerTokensControl.parse(invalid), isNull, reason: invalid);
    }
  });

  testWidgets('Custom dialog validates and preserves requests beyond context', (
    tester,
  ) async {
    var value = 1024;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) => AnswerTokensControl(
            label: 'Max answer tokens',
            value: value,
            contextWindow: 65536,
            onChanged: (v) => setState(() => value = v),
          ),
        ),
      ),
    );
    expect(tester.widget<Slider>(find.byType(Slider)).max, 64000);
    expect(find.text('1,024'), findsOneWidget);

    await tester.tap(find.byKey(const Key('answer-tokens-custom')));
    await tester.pumpAndSettle();
    final input = find.byKey(const Key('answer-tokens-input'));
    await tester.enterText(input, 'abc');
    await tester.tap(find.text(_en.uiSettingsWidgetsApply));
    await tester.pumpAndSettle();
    expect(find.text(_en.answerTokensInvalid), findsOneWidget);
    expect(value, 1024);

    await tester.enterText(input, '128,000');
    await tester.tap(find.text(_en.uiSettingsWidgetsApply));
    await tester.pumpAndSettle();
    expect(value, 128000);
    expect(find.text('128,000'), findsOneWidget);
    expect(find.text(_en.answerTokensContextLimit(65536)), findsOneWidget);
  });

  testWidgets('saved custom values display without clamping', (tester) async {
    await tester.pumpWidget(
      _app(
        AnswerTokensControl(
          label: 'Max answer tokens',
          value: 128000,
          contextWindow: 4096,
          onChanged: (_) => fail('Building must not overwrite a saved request'),
        ),
      ),
    );
    expect(find.text('128,000'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 64000);
  });
}
