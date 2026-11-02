import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/attachments/data/attachment_store.dart';
import '../features/attachments/domain/attachment.dart';
import '../features/chat/domain/chat_draft_store.dart';

class DesktopChatDraft {
  final String text;
  final List<Attachment> attachments;
  const DesktopChatDraft(this.text, this.attachments);
}

/// Drafts outlive section widgets. Pending files belong to the draft
/// until a send transfers them to chat, or the draft is discarded.
class DesktopChatDrafts {
  final _drafts = <String, DesktopChatDraft>{};
  final Future<void> Function(Attachment) _delete;
  final ChatDraftStore _store;
  final _timers = <String, Timer>{};
  final bool persist;

  DesktopChatDrafts({
    Future<void> Function(Attachment)? delete,
    ChatDraftStore? store,
    this.persist = true,
  }) : _delete = delete ?? AttachmentStore.delete,
       _store = store ?? ChatDraftStore();

  DesktopChatDraft read(String key) =>
      _drafts[key] ?? const DesktopChatDraft('', []);

  Future<DesktopChatDraft> load(String key) async {
    if (_drafts.containsKey(key) || key == 'temporary' || !persist) {
      return read(key);
    }
    final saved = await _store.read('desktop:$key');
    // Typing or sending while the disk read was pending wins over disk.
    return _drafts.putIfAbsent(
      key,
      () => DesktopChatDraft(saved.text, saved.attachments),
    );
  }

  Future<void> flush(String key) async {
    _timers.remove(key)?.cancel();
    if (!persist || key == 'temporary' || !_drafts.containsKey(key)) return;
    final draft = read(key);
    await _store.save(
      'desktop:$key',
      ChatDraft(text: draft.text, attachments: draft.attachments),
    );
  }

  void save(
    String key,
    DesktopChatDraft draft, {
    void Function(Object)? onError,
  }) {
    _drafts[key] = draft;
    _timers.remove(key)?.cancel();
    if (!persist || key == 'temporary') return;
    _timers[key] = Timer(const Duration(milliseconds: 350), () {
      unawaited(flush(key).catchError((Object error) => onError?.call(error)));
    });
  }

  void discard(String key) {
    _timers.remove(key)?.cancel();
    final draft = _drafts.remove(key);
    for (final attachment in draft?.attachments ?? <Attachment>[]) {
      unawaited(_delete(attachment));
    }
  }

  Future<void> remove(String key) async {
    final draft = await load(key);
    save(key, const DesktopChatDraft('', []));
    await flush(key);
    for (final attachment in draft.attachments) {
      await _delete(attachment);
    }
  }

  void dispose() {
    for (final key in _drafts.keys.toList()) {
      if (key == 'temporary' || !persist) {
        discard(key);
      } else {
        // Persisted drafts retain ownership of their files across restarts.
        unawaited(flush(key).catchError((Object _) {}));
      }
    }
  }
}

final desktopChatDraftsProvider = Provider<DesktopChatDrafts>((ref) {
  final drafts = DesktopChatDrafts();
  ref.onDispose(drafts.dispose);
  return drafts;
});
