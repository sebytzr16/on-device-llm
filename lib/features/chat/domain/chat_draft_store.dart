import 'dart:convert';
import 'dart:io';
import '../../../core/storage/device_encryption.dart';
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
  final DeviceEncryption encryption;
  Future<void> _writes = Future.value();
  ChatDraftStore({
    Future<Directory> Function()? root,
    DeviceEncryption? encryption,
  }) : root = root ?? getApplicationSupportDirectory,
       encryption = encryption ?? DeviceEncryption.instance;
  static String _fileName(String key) =>
      '${base64Url.encode(utf8.encode(key)).replaceAll('=', '')}.json';

  static String? _keyOf(String name) {
    final base = name.endsWith('.json')
        ? name.substring(0, name.length - 5)
        : name;
    if (base.isEmpty) return null;
    try {
      return utf8.decode(
        base64Url.decode(base + '=' * ((4 - base.length % 4) % 4)),
      );
    } on FormatException {
      return null;
    }
  }

  Future<File> _file(String key) async {
    final dir = Directory(p.join((await root()).path, 'drafts'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, _fileName(key)));
  }

  /// Keys of the drafts on disk, including a `.bak` a crash left behind.
  Future<List<String>> keys() async {
    await _writes;
    final dir = Directory(p.join((await root()).path, 'drafts'));
    if (!await dir.exists()) return const [];
    final out = <String>{};
    await for (final file in dir.list(followLinks: false)) {
      if (file is! File) continue;
      var name = p.basename(file.path);
      for (final suffix in ['.enc-original', '.enc-pending', '.bak']) {
        if (name.endsWith(suffix)) {
          name = name.substring(0, name.length - suffix.length);
        }
      }
      if (!name.endsWith('.json')) continue;
      final key = _keyOf(name);
      if (key != null) out.add(key);
    }
    return out.toList();
  }

  /// Deletes the stored draft [key] and the crash backups beside it.
  Future<void> delete(String key) {
    final write = _writes.then((_) async {
      final file = await _file(key);
      for (final stale in [
        file,
        File('${file.path}.bak'),
        File('${file.path}.tmp'),
        File('${file.path}.enc-original'),
        File('${file.path}.enc-pending'),
      ]) {
        if (await stale.exists()) await stale.delete();
      }
    });
    _writes = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  Future<ChatDraft> read(String key) async {
    await _writes;
    final file = await _file(key);
    final backup = File('${file.path}.bak');
    final original = File('${file.path}.enc-original');
    final pending = File('${file.path}.enc-pending');
    final source = await file.exists()
        ? file
        : await original.exists()
        ? original
        : await pending.exists()
        ? pending
        : backup;
    if (!await source.exists()) return const ChatDraft();
    final j =
        jsonDecode(utf8.decode(await encryption.read(source)))
            as Map<String, dynamic>;
    return ChatDraft(
      text: j['text'] as String? ?? '',
      attachments: Attachment.listFromJson(j['attachments']),
    );
  }

  Future<void> save(String key, ChatDraft draft) {
    final write = _writes.then((_) async {
      final file = await _file(key);
      final backup = File('${file.path}.bak');
      if (await file.exists()) await encryption.read(file);
      if (await backup.exists()) await encryption.read(backup);
      if (draft.isEmpty) {
        if (await file.exists()) await file.delete();
        if (await backup.exists()) await backup.delete();
        return;
      }
      await encryption.write(file, utf8.encode(jsonEncode(draft.toJson())));
      if (await backup.exists()) await backup.delete();
    });
    _writes = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
