import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/storage/device_encryption.dart';
import 'package:ondevice_llm/core/storage/native_media_lease.dart';
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';
import 'package:ondevice_llm/features/knowledge/document_embedding_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hosting_secure_storage.dart';

class UnreadableVault extends MemoryHostSecrets {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => throw StateError('Secure storage is locked');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late MemoryHostSecrets vault;
  late SharedPreferences prefs;
  late DeviceEncryption encryption;

  DeviceEncryption service({FlutterSecureStorage? storage}) => DeviceEncryption(
    storage: storage ?? vault,
    preferences: () async => prefs,
    directories: () async => [root],
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    root = await Directory.systemTemp.createTemp('device-encryption-');
    vault = MemoryHostSecrets();
    encryption = service();
  });
  tearDown(() => root.delete(recursive: true));

  testWidgets('an idle queue can be reused for real I/O outside fake async', (
    tester,
  ) async {
    expect(await encryption.readGoal('missing'), isNull);
    await tester.runAsync(() async {
      final file = File('${root.path}/outside.txt');
      await encryption.write(file, utf8.encode('outside'));
      expect(utf8.decode(await encryption.read(file)), 'outside');
    });
    expect(await encryption.readGoal('missing'), isNull);
  });

  test('off by default: plaintext and no data key', () async {
    final file = File('${root.path}/legacy.json');
    await encryption.write(file, utf8.encode('draft'));
    expect(await encryption.enabled(), isFalse);
    expect(await file.readAsString(), 'draft');
    expect(vault.values, isEmpty);
  });

  test(
    'AES-GCM binary round-trip survives restart with independent nonces',
    () async {
      await encryption.setEnabled(true);
      final data = List<int>.generate(256, (i) => i);
      final a = File('${root.path}/a.png');
      final b = File('${root.path}/b.png');
      await encryption.write(a, data);
      await encryption.write(b, data);
      expect(DeviceEncryption.isEncrypted(await a.readAsBytes()), isTrue);
      expect(await a.readAsBytes(), isNot(await b.readAsBytes()));
      encryption = service();
      expect(await encryption.read(a), data);
      expect(await encryption.read(b), data);
      expect(base64Decode(vault.values[DeviceEncryption.keyName]!).length, 32);
      expect(prefs.getKeys(), {
        DeviceEncryption.settingKey,
        DeviceEncryption.migrationKey,
      });
    },
  );

  test('a queued toggle off converts an in-flight encrypted write', () async {
    await encryption.setEnabled(true);
    final file = File('${root.path}/queued.json');
    await Future.wait([
      encryption.write(file, utf8.encode('queued content')),
      encryption.setEnabled(false),
    ]);
    expect(await encryption.enabled(), isFalse);
    expect(await file.readAsString(), 'queued content');
  });

  test(
    'legacy plaintext reads while enabled and migrates on next write',
    () async {
      await encryption.setEnabled(true);
      final file = File('${root.path}/legacy.json');
      await file.writeAsString('old draft');
      expect(utf8.decode(await encryption.read(file)), 'old draft');
      expect(await file.readAsString(), 'old draft');
      await encryption.write(file, utf8.encode('new draft'));
      expect(DeviceEncryption.isEncrypted(await file.readAsBytes()), isTrue);
      expect(utf8.decode(await encryption.read(file)), 'new draft');
    },
  );

  test(
    'toggle migrates all files and Goals; off decrypts and retains key',
    () async {
      final file = File('${root.path}/draft.json');
      await file.writeAsString('legacy content');
      await prefs.setString('goal_history_v1', '[{"report":"private"}]');
      await encryption.setEnabled(true);
      final key = vault.values[DeviceEncryption.keyName];
      expect(DeviceEncryption.isEncrypted(await file.readAsBytes()), isTrue);
      expect(prefs.getString('goal_history_v1'), startsWith('ODLENC1:'));
      expect(
        await encryption.readGoal('goal_history_v1'),
        '[{"report":"private"}]',
      );
      await encryption.writeGoal('goal_draft_v1', '{"objective":"saved"}');
      await encryption.setEnabled(false);
      expect(await file.readAsString(), 'legacy content');
      expect(prefs.getString('goal_history_v1'), '[{"report":"private"}]');
      expect(prefs.getString('goal_draft_v1'), '{"objective":"saved"}');
      expect(vault.values[DeviceEncryption.keyName], key);
      await encryption.setEnabled(true);
      expect(vault.values[DeviceEncryption.keyName], key);
    },
  );

  for (final failure in [
    'missing',
    'wrong',
    'malformed',
    'unreadable',
    'tampered',
    'version',
  ]) {
    test(
      '$failure key/envelope gives recovery and preserves every original',
      () async {
        await encryption.setEnabled(true);
        final file = File('${root.path}/private.bin');
        await encryption.write(file, [0, 1, 2, 255]);
        await encryption.writeGoal('goal_draft_v1', '{"objective":"private"}');
        if (failure == 'missing') vault.values.clear();
        if (failure == 'wrong')
          vault.values[DeviceEncryption.keyName] = base64Encode(
            List.filled(32, 42),
          );
        if (failure == 'malformed')
          vault.values[DeviceEncryption.keyName] = 'not a key';
        if (failure == 'unreadable')
          encryption = service(storage: UnreadableVault());
        if (failure == 'tampered' || failure == 'version') {
          final bytes = await file.readAsBytes();
          bytes[failure == 'version' ? 7 : bytes.length - 1] ^= 1;
          await file.writeAsBytes(bytes);
        }
        final original = await file.readAsBytes();
        final goal = prefs.getString('goal_draft_v1');
        await expectLater(
          encryption.read(file),
          throwsA(isA<EncryptionRecovery>()),
        );
        await expectLater(
          encryption.write(file, [9]),
          throwsA(isA<EncryptionRecovery>()),
        );
        await expectLater(
          encryption.setEnabled(false),
          throwsA(isA<EncryptionRecovery>()),
        );
        await expectLater(
          encryption.setEnabled(true),
          throwsA(isA<EncryptionRecovery>()),
        );
        expect(await file.readAsBytes(), original);
        expect(prefs.getString('goal_draft_v1'), goal);
        expect(await encryption.enabled(), isTrue);
        expect(encryption.recovery.value, isTrue);
        expect(
          const EncryptionRecovery().toString(),
          contains('No data was deleted'),
        );
        if (failure == 'missing') expect(vault.values, isEmpty);
      },
    );
  }

  test(
    'unreadable Goals return unavailable and cannot be overwritten or removed',
    () async {
      await encryption.setEnabled(true);
      await encryption.writeGoal('goal_draft_v1', '{"objective":"private"}');
      final original = prefs.getString('goal_draft_v1');
      vault.values.clear();
      expect(await encryption.readGoal('goal_draft_v1'), isNull);
      await expectLater(
        encryption.writeGoal('goal_draft_v1', '{}'),
        throwsA(isA<EncryptionRecovery>()),
      );
      await expectLater(
        encryption.removeGoal('goal_draft_v1'),
        throwsA(isA<EncryptionRecovery>()),
      );
      expect(prefs.getString('goal_draft_v1'), original);
    },
  );

  test(
    'failed secure-storage write does not enable encryption or touch legacy data',
    () async {
      final file = File('${root.path}/legacy.json');
      await file.writeAsString('keep');
      vault.failWrites = true;
      await expectLater(
        encryption.setEnabled(true),
        throwsA(isA<EncryptionRecovery>()),
      );
      expect(await encryption.enabled(), isFalse);
      expect(await file.readAsString(), 'keep');
    },
  );

  test(
    'interrupted replacement reads original and retry finishes migration',
    () async {
      final original = File('${root.path}/draft.json.enc-original');
      await original.writeAsString('recoverable');
      final target = File('${root.path}/draft.json');
      expect(utf8.decode(await encryption.read(target)), 'recoverable');
      await encryption.setEnabled(true);
      expect(DeviceEncryption.isEncrypted(await target.readAsBytes()), isTrue);
      expect(utf8.decode(await encryption.read(target)), 'recoverable');
      expect(await original.exists(), isFalse);
    },
  );

  test(
    'chat drafts use the envelope and an empty autosave cannot erase key-lost data',
    () async {
      final store = ChatDraftStore(
        root: () async => root,
        encryption: encryption,
      );
      await store.save('chat', const ChatDraft(text: 'legacy'));
      // The service migration root is flat; draft files live one level deeper.
      await encryption.setEnabled(true);
      expect((await store.read('chat')).text, 'legacy');
      await store.save('chat', const ChatDraft(text: 'encrypted'));
      final file = (await Directory(
        '${root.path}/drafts',
      ).list().toList()).whereType<File>().single;
      expect(DeviceEncryption.isEncrypted(await file.readAsBytes()), isTrue);
      final original = await file.readAsBytes();
      vault.values.clear();
      await expectLater(store.read('chat'), throwsA(isA<EncryptionRecovery>()));
      await expectLater(
        store.save('chat', const ChatDraft()),
        throwsA(isA<EncryptionRecovery>()),
      );
      expect(await file.readAsBytes(), original);
    },
  );

  test(
    'encrypted vector cache reopens and never evicts key-lost files',
    () async {
      final dir = Directory('${root.path}/vectors');
      await encryption.setEnabled(true);
      var calls = 0;
      Future<List<Float32List>?> compute() async {
        calls++;
        return [
          Float32List.fromList([0.5, 0.5]),
        ];
      }

      DocumentEmbeddingCache cache() => DocumentEmbeddingCache(
        directory: () async => dir,
        encryption: encryption,
        diskBytes: 80,
      );
      await cache().vectors('model', ['first'], compute);
      final file = (await dir.list().toList()).whereType<File>().single;
      final original = await file.readAsBytes();
      expect(DeviceEncryption.isEncrypted(original), isTrue);
      await cache().vectors('model', ['first'], compute);
      expect(calls, 1);
      vault.values.clear();
      expect(await cache().vectors('model', ['first'], compute), isNotNull);
      await cache().vectors('model', ['second'], compute);
      expect(await file.readAsBytes(), original);
      expect((await dir.list().toList()).length, 1);
    },
  );

  test(
    'native vision receives a temporary plaintext file and cleans it up',
    () async {
      await encryption.setEnabled(true);
      final image = File('${root.path}/photo.png');
      await encryption.write(image, [137, 80, 78, 71]);
      final lease = await NativeMediaLease.open(
        [
          {
            'role': 'user',
            'content': 'photo',
            'images': [image.path],
          },
        ],
        encryption: encryption,
        temporaryDirectory: () async => root,
      );
      final path = (lease.messages.single['images'] as List).single as String;
      expect(path, isNot(image.path));
      expect(await File(path).readAsBytes(), [137, 80, 78, 71]);
      expect(DeviceEncryption.isEncrypted(await image.readAsBytes()), isTrue);
      await lease.dispose();
      expect(await File(path).exists(), isFalse);
      expect(await image.exists(), isTrue);
    },
  );

  test(
    'native vision key failure never hands encrypted bytes to the decoder',
    () async {
      await encryption.setEnabled(true);
      final image = File('${root.path}/photo.png');
      await encryption.write(image, [1, 2, 3]);
      vault.values.clear();
      await expectLater(
        NativeMediaLease.open(
          [
            {
              'role': 'user',
              'content': 'photo',
              'images': [image.path],
            },
          ],
          encryption: encryption,
          temporaryDirectory: () async => root,
        ),
        throwsA(isA<EncryptionRecovery>()),
      );
      expect((await root.list().toList()).whereType<Directory>(), isEmpty);
      expect(await image.exists(), isTrue);
    },
  );

  test(
    'native watch envelopes retain the scheduling id and decrypt in a new engine',
    () async {
      await encryption.setEnabled(true);
      final row = {'id': 7, 'objective': 'private question'};
      final encoded = await encryption.encodeText(jsonEncode(row));
      final raw = jsonEncode([
        {'id': 7, 'encrypted': encoded},
      ]);
      expect(raw, isNot(contains('private question')));
      expect(await service().decodeWatches(raw), [row]);
      vault.values.clear();
      await expectLater(
        service().decodeWatches(raw),
        throwsA(isA<EncryptionRecovery>()),
      );
    },
  );
}
