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

class _CountingFiles extends DeviceEncryption {
  final reads = <String>[];
  @override
  Future<Uint8List> read(File file) async {
    reads.add(file.path);
    return _png;
  }
}

/// The vault without its key: reading reports it, as `_unavailable()` does.
class _LockedVault extends DeviceEncryption {
  var reads = 0;
  var locked = true;
  @override
  Future<Uint8List> read(File file) async {
    reads++;
    if (locked) {
      recovery.value = true;
      throw const EncryptionRecovery();
    }
    recovery.value = false;
    return _png;
  }
}

/// A composer rebuild (a keystroke) must not decrypt the pending photos again
/// nor drop their thumbnails back to the placeholder (audit 08b-1).
void main() {
  testWidgets('a rebuild keeps the decrypted thumbnail and its future', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('odl_thumb_');
    final previous = DeviceEncryption.instance;
    final files = _CountingFiles();
    DeviceEncryption.instance = files;
    addTearDown(() => DeviceEncryption.instance = previous);
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    Attachment picture(String id, String name) => Attachment(
      id: id,
      kind: AttachmentKind.image,
      name: name,
      mime: 'image/png',
      path: '${dir.path}/$name',
      sizeBytes: _png.length,
    );
    final one = picture('one', 'one.png');
    final two = picture('two', 'two.png');

    Widget app(Attachment a) => MaterialApp(
      theme: AppTheme.dark,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: AttachmentChips(attachments: [a])),
    );

    await tester.pumpWidget(app(one));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-one')), findsOneWidget);
    expect(files.reads, [one.path]);

    // Same picture, the composer rebuilds: one decryption per attachment.
    await tester.pumpWidget(app(one));
    await tester.pump();
    expect(find.byKey(const Key('attachment-one')), findsOneWidget);
    expect(files.reads, [one.path]);

    // Another picture in the same slot is read once, by its own path.
    await tester.pumpWidget(app(two));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-two')), findsOneWidget);
    expect(files.reads, [one.path, two.path]);
  });

  testWidgets('a locked picture is retried once the vault is usable again', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('odl_locked_');
    final previous = DeviceEncryption.instance;
    final vault = _LockedVault();
    DeviceEncryption.instance = vault;
    addTearDown(() => DeviceEncryption.instance = previous);
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final picture = Attachment(
      id: 'locked',
      kind: AttachmentKind.image,
      name: 'locked.png',
      mime: 'image/png',
      path: '${dir.path}/locked.png',
      sizeBytes: _png.length,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AttachmentChips(attachments: [picture])),
      ),
    );
    await tester.pumpAndSettle();
    // No key: the placeholder, read once.
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(vault.reads, 1);

    // Vault access is restored (EncryptionRecovery): the picture must come
    // back instead of staying locked until the composer is reopened.
    vault.locked = false;
    vault.recovery.value = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('attachment-locked')), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsNothing);
    expect(vault.reads, 2);
  });
}
