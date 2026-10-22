import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/empty_state.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';

void main() {
  for (final language in ['en', 'fr', 'es']) {
    testWidgets('a remote model is never described as on-device ($language)', (
      tester,
    ) async {
      final t = lookupAppLocalizations(Locale(language));
      Future<void> show(String? host) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            locale: Locale(language),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Scaffold(
              body: ChatEmptyState(hasModel: true, remoteHost: host),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show('gemini.example');
      expect(find.text(t.emptyRemote('gemini.example')), findsOneWidget);
      expect(find.text(t.emptyHasModel), findsNothing);
      await show(null);
      expect(find.text(t.emptyHasModel), findsOneWidget);
    });
  }
}
