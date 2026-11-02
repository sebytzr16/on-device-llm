import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:ondevice_llm/features/attachments/domain/document_text.dart';
import 'package:ondevice_llm/features/chat/presentation/widgets/reasoning_accordion.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  test('new user-facing translations preserve accents and placeholders', () {
    final en =
        jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map;
    for (final language in ['fr', 'es']) {
      final translated =
          jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
              as Map;
      for (final entry in en.entries) {
        final key = entry.key as String;
        if (!key.startsWith('image') &&
            !key.startsWith('document') &&
            !key.startsWith('reasoning') &&
            !key.startsWith('mtp') &&
            !key.startsWith('schedule') &&
            !key.startsWith('hostPair')) {
          continue;
        }
        expect(translated.containsKey(key), isTrue, reason: '$language $key');
        if (!(entry.value as String).contains('?')) {
          expect(
            translated[key],
            isNot(contains('?')),
            reason: '$language $key',
          );
        }
        final placeholders = RegExp(
          r'\{(\w+)\}',
        ).allMatches(entry.value as String).map((m) => m[1]).toSet();
        expect(
          RegExp(
            r'\{(\w+)\}',
          ).allMatches(translated[key] as String).map((m) => m[1]).toSet(),
          placeholders,
          reason: '$language $key',
        );
      }
    }
  });

  for (final language in ['fr', 'es']) {
    test(
      'document errors stay localized on background isolates: $language',
      () async {
        final t = stringsFor(language);
        await expectLater(
          DocumentText.extract(Uint8List(0), 'file.pdf', localeCode: language),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              t.documentPdfUnavailable,
            ),
          ),
        );
        await expectLater(
          DocumentText.extract(
            Uint8List(DocumentText.isolateThreshold + 1),
            'file.bin',
            localeCode: language,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              t.documentUnsupported(' (.bin)'),
            ),
          ),
        );
        await expectLater(
          AttachmentStore.import(
            name: 'large.txt',
            bytes: Uint8List(AttachmentStore.maxDocumentBytes + 1),
            localeCode: language,
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              t.documentTooLarge,
            ),
          ),
        );
      },
    );

    test('MTP errors use the selected locale without mojibake: $language', () {
      const target = GgufMetadata(
        version: 3,
        tensorCount: 1,
        architecture: 'qwen35',
      );
      const head = GgufMetadata(
        version: 3,
        tensorCount: 1,
        architecture: 'gemma4-assistant',
      );
      final t = stringsFor(language);
      expect(target.mtpHeadIssueFor(target, strings: t), t.mtpFullModel);
      final issue = head.mtpHeadIssueFor(target, strings: t)!;
      expect(issue, t.mtpIncompatible('gemma4-assistant', 'qwen35'));
      expect(issue, isNot(contains('?')));
    });

    testWidgets('reasoning title uses the app locale: $language', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: const Scaffold(
            body: ReasoningAccordion(
              content: 'Working',
              isComplete: true,
              duration: Duration(seconds: 3),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(stringsFor(language).reasoningDuration('3.0')),
        findsOneWidget,
      );
    });
  }
}
