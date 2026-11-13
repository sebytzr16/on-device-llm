import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/storage/device_encryption.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/attachments/presentation/attachment_chips.dart';
import 'package:ondevice_llm/l10n/app_localizations.dart';

// 1x1 transparent PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

class _PlainFiles extends DeviceEncryption {
  @override
  Future<Uint8List> read(File file) async => _png;
}

void main() {
  testWidgets('a sent picture opens full size with Save and Close', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('odl_viewer_');
    final previous = DeviceEncryption.instance;
    DeviceEncryption.instance = _PlainFiles();
    addTearDown(() => DeviceEncryption.instance = previous);
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File('${dir.path}/picture.png')..writeAsBytesSync(_png);
    final a = Attachment(
      id: 'gen1',
      kind: AttachmentKind.image,
      name: 'picture.png',
      mime: 'image/png',
      path: file.path,
      sizeBytes: _png.length,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AttachmentChips(attachments: [a], large: true)),
      ),
    );
    await tester.pumpAndSettle();
    final thumb = find.byKey(const Key('attachment-gen1'));
    expect(thumb, findsOneWidget);
    expect(tester.getSize(thumb), const Size(240, 240));

    await tester.tap(thumb);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-viewer-image')), findsOneWidget);
    expect(find.byKey(const Key('attachment-viewer-save')), findsOneWidget);

    await tester.tap(find.byKey(const Key('attachment-viewer-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-viewer-image')), findsNothing);
  });
}
