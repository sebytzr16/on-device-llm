import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/attachments/domain/scan_options.dart';
import 'package:ondevice_llm/features/attachments/presentation/attachment_picker.dart';

void main() {
  testWidgets(
    'Back cancels import and completion removes only its dialog (P2-51)',
    (tester) async {
      final release = Completer<void>();
      var imports = 0;
      late bool Function() isCancelled;
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (value) {
              context = value;
              return const Scaffold(body: Text('Import page'));
            },
          ),
        ),
      );
      final job = importAttachments(
        context,
        [
          ('first.txt', null, Uint8List.fromList([65])),
          ('second.txt', null, Uint8List.fromList([66])),
        ],
        importFile:
            ({required name, sourcePath, bytes, cancelled, progress}) async {
              imports++;
              isCancelled = cancelled!;
              await release.future;
              expect(isCancelled(), isTrue);
              throw const ScanCancelled();
            },
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(isCancelled(), isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final navigator = Navigator.of(context);
      final other = DialogRoute<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('Other dialog')),
      );
      unawaited(navigator.push(other));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      release.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      final result = await job;
      expect(result, isEmpty);
      expect(imports, 1, reason: 'the second file must not start');
      expect(other.isCurrent, isTrue);
      expect(find.text('Other dialog'), findsOneWidget);
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text('Import page'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
