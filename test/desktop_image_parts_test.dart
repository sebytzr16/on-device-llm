import 'dart:io';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ondevice_llm/core/platform/desktop_host.dart';
import 'package:ondevice_llm/desktop/chat_drafts.dart';
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/features/image_gen/domain/entities/image_gen_model.dart';
import 'package:ondevice_llm/features/image_gen/image_gen_downloads.dart';

import 'local_backup_service_test.dart' show BackupPaths;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'P1-24 durable drafts restore files, clear on deletion, and never persist temporary chat',
    () async {
      final root = await Directory.systemTemp.createTemp('desktop-drafts-');
      final store = ChatDraftStore(root: () async => root);
      final deleted = <String>[];
      final drafts = DesktopChatDrafts(
        store: store,
        delete: (a) async {
          deleted.add(a.id);
        },
      );
      const attachment = Attachment(
        id: 'a',
        kind: AttachmentKind.document,
        name: 'a',
        mime: 'text/plain',
        path: 'a',
        sizeBytes: 1,
      );
      try {
        drafts.save('chat', const DesktopChatDraft('draft', [attachment]));
        await drafts.flush('chat');
        drafts.save('temporary', const DesktopChatDraft('private', []));
        await drafts.flush('temporary');
        final restored = DesktopChatDrafts(
          store: store,
          delete: (a) async {
            deleted.add(a.id);
          },
        );
        expect((await restored.load('chat')).text, 'draft');
        expect(restored.read('chat').attachments.single.id, 'a');
        expect((await store.read('desktop:temporary')).isEmpty, isTrue);
        await restored.remove('chat');
        expect((await store.read('desktop:chat')).isEmpty, isTrue);
        expect(deleted, ['a']);
        // A pending disk read must not replace a newly typed draft.
        final gate = Completer<Directory>();
        final racing = DesktopChatDrafts(
          store: ChatDraftStore(root: () => gate.future),
        );
        final loading = racing.load('other');
        racing.save('other', const DesktopChatDraft('typed', []));
        gate.complete(root);
        expect((await loading).text, 'typed');
        await racing.flush('other');
      } finally {
        // Explicit flushes above also cancel the debounce timers.
        await root.delete(recursive: true);
      }
    },
  );

  test(
    'P2-26 deleting last variant removes shared parts; cleanup preserves installed variants',
    () async {
      final root = await Directory.systemTemp.createTemp('image-parts-');
      final previous = PathProviderPlatform.instance;
      final desktop = DesktopHost.active;
      DesktopHost.active = false;
      PathProviderPlatform.instance = BackupPaths(root.path, root.path);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      try {
        final variants = imageGenCatalog
            .where((m) => m.id.startsWith('qwen'))
            .toList();
        expect(variants.length, greaterThan(1));
        final a = variants[0], b = variants[1];
        for (final f in {...a.files, ...b.files}) {
          await (await ModelStorage.modelFile(
            f.fileName,
          )).writeAsString('component');
        }
        final downloads = container.read(imageGenDownloadsProvider.notifier);
        await downloads.delete(a);
        for (final f in b.files) {
          expect(await ModelStorage.exists(f.fileName), isTrue);
        }
        await downloads.removeUnusedParts();
        for (final f in b.files) {
          expect(await ModelStorage.exists(f.fileName), isTrue);
        }
        await downloads.delete(b);
        final toolFiles = upscalerTools
            .expand((m) => m.files)
            .map((f) => f.fileName)
            .toSet();
        for (final f in b.files) {
          expect(
            await ModelStorage.exists(f.fileName),
            toolFiles.contains(f.fileName),
          );
        }
        // Leftovers from an interrupted/old download can be removed explicitly.
        await (await ModelStorage.modelFile(
          b.files.first.fileName,
        )).writeAsString('orphan');
        await downloads.removeUnusedParts();
        expect(await ModelStorage.exists(b.files.first.fileName), isFalse);
      } finally {
        container.dispose();
        PathProviderPlatform.instance = previous;
        DesktopHost.active = desktop;
        await root.delete(recursive: true);
      }
    },
  );
}
