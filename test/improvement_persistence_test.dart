import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/utils/priority_work_queue.dart';
import 'package:ondevice_llm/features/backup/backup_cipher.dart';
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';
import 'package:ondevice_llm/features/chat/domain/export/document_draft_store.dart';
import 'package:ondevice_llm/inference/remote/remote_provider.dart';

void main() {
  test(
    'streamed encryption interoperates with existing backup envelopes',
    () async {
      final dir = await Directory.systemTemp.createTemp('odllm-cipher-');
      addTearDown(() => dir.delete(recursive: true));
      final plain = File('${dir.path}/plain');
      final encrypted = File('${dir.path}/encrypted');
      final restored = File('${dir.path}/restored');
      final bytes = Uint8List.fromList(List.generate(200000, (i) => i % 251));
      const password = 'a strong backup password';
      await plain.writeAsBytes(bytes);
      await BackupCipher.encryptFile(plain, encrypted, password);
      expect(
        await BackupCipher.decrypt(await encrypted.readAsBytes(), password),
        bytes,
      );
      await encrypted.writeAsBytes(await BackupCipher.encrypt(bytes, password));
      await BackupCipher.decryptFile(encrypted, restored, password);
      expect(await restored.readAsBytes(), bytes);
      final damaged = await encrypted.readAsBytes();
      damaged[damaged.length - 1] ^= 1;
      await encrypted.writeAsBytes(damaged);
      await expectLater(
        BackupCipher.decryptFile(encrypted, restored, password),
        throwsFormatException,
      );
      expect(
        await restored.exists(),
        isFalse,
        reason: 'Unauthenticated plaintext must be removed.',
      );
    },
  );

  test(
    'interactive work goes ahead of queued indexing and errors release ownership',
    () async {
      final queue = PriorityWorkQueue();
      final gate = Completer<void>();
      final order = <String>[];
      final first = queue.submit(() async {
        order.add('active');
        await gate.future;
      });
      final background = queue.submit(() async => order.add('index'));
      final interactive = queue.submit(
        () async => order.add('query'),
        priority: 10,
      );
      gate.complete();
      await Future.wait([first, background, interactive]);
      expect(order, ['active', 'query', 'index']);
      await expectLater(
        queue.submit(() async => throw StateError('fixture')),
        throwsStateError,
      );
      expect(await queue.submit(() async => 42), 42);
    },
  );

  test(
    'concurrent document saves retain ordered revisions and isolate templates',
    () async {
      final dir = await Directory.systemTemp.createTemp('odllm-revisions-');
      addTearDown(() => dir.delete(recursive: true));
      final drafts = ChatDraftStore(root: () async => dir);
      final store = DocumentDraftStore(drafts: drafts);
      await Future.wait([
        store.save('chat', 'report', 'First'),
        store.save('chat', 'report', 'Second'),
      ]);
      final versions = await store.read('chat', 'report');
      expect(versions.map((v) => v.content), ['Second', 'First']);
      await store.save('chat', 'report', 'Second');
      expect(await store.read('chat', 'report'), hasLength(2));
      expect(await store.read('chat', 'letter'), isEmpty);
    },
  );

  test('remote connections default to no memory sharing or learning', () {
    final profile = RemoteProfile.fromJson({
      'id': 'server',
      'baseUrl': 'https://example.com',
    })!;
    expect(profile.shareMemory, isFalse);
    expect(profile.learnMemory, isFalse);
    final changed = profile.copyWith(shareMemory: true, learnMemory: true);
    final restored = RemoteProfile.fromJson(changed.toJson())!;
    expect(restored.shareMemory, isTrue);
    expect(restored.learnMemory, isTrue);
  });
}
