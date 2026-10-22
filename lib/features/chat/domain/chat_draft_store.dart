import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../attachments/domain/attachment.dart';

class ChatDraft {
  final String text;
  final List<Attachment> attachments;
  const ChatDraft({this.text = '', this.attachments = const []});
  bool get isEmpty => text.isEmpty && attachments.isEmpty;
  Map<String, dynamic> toJson() => {
    'text': text,
    'attachments': [for (final a in attachments) a.toJson()],
  };
}

class ChatDraftStore {
  final Future<Directory> Function() root;
  Future<void> _writes = Future.value();
  ChatDraftStore({Future<Directory> Function()? root})
    : root = root ?? getApplicationSupportDirectory;
  Future<File> _file(String key) async {
    final dir = Directory(p.join((await root()).path, 'drafts'));
    await dir.create(recursive: true);
    return File(
      p.join(
        dir.path,
        '${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}.json',
      ),
    );
  }

  Future<ChatDraft> read(String key) async {
    await _writes;
    final file = await _file(key);
    final backup = File('${file.path}.bak');
    final source = await file.exists() ? file : backup;
    if (!await source.exists()) return const ChatDraft();
    final j = jsonDecode(await source.readAsString()) as Map<String, dynamic>;
    return ChatDraft(
      text: j['text'] as String? ?? '',
      attachments: Attachment.listFromJson(j['attachments']),
    );
  }

  Future<void> save(String key, ChatDraft draft) {
    final write = _writes.then((_) async {
      final file = await _file(key);
      final backup = File('${file.path}.bak');
      if (draft.isEmpty) {
        if (await file.exists()) await file.delete();
        if (await backup.exists()) await backup.delete();
        return;
      }
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(draft.toJson()), flush: true);
      if (await backup.exists()) await backup.delete();
      if (await file.exists()) await file.rename(backup.path);
      await temp.rename(file.path);
      if (await backup.exists()) await backup.delete();
    });
    _writes = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
