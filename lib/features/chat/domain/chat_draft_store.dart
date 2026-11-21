import 'dart:convert';
import 'dart:io';
import '../../../core/storage/device_encryption.dart';
import 'package:logging/logging.dart';
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
    final write = _writes.then((_) async => _deleteArtifacts(await _file(key)));
    _writes = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }

  List<File> _readCandidates(File file) => [
    File('${file.path}.enc-pending'),
    file,
    File('${file.path}.enc-original'),
    File('${file.path}.bak'),
  ];

  Future<void> _deleteArtifacts(File file) async {
    for (final stale in [..._readCandidates(file), File('${file.path}.tmp')]) {
      if (await stale.exists()) await stale.delete();
    }
  }

  Future<ChatDraft> read(String key) async {
    await _writes;
    final file = await _file(key);
    EncryptionRecovery? locked;
    // The replacement flushes pending before moving the previous draft aside.
    for (final source in _readCandidates(file)) {
      try {
        if (!await source.exists()) continue;
        final json = jsonDecode(utf8.decode(await encryption.read(source)));
        if (json is! Map<String, dynamic>) {
          throw const FormatException('Expected a draft object');
        }
        final rawText = json['text'];
        final text = rawText is String ? rawText : '';
        final rawAttachments = json['attachments'];
        final attachments = <Attachment>[];
        var damaged =
            (rawText != null && rawText is! String) ||
            (rawAttachments != null && rawAttachments is! List);
        if (rawAttachments is List) {
          for (final entry in rawAttachments) {
            if (entry is! Map<String, dynamic>) {
              damaged = true;
              continue;
            }
            try {
              attachments.add(Attachment.fromJson(entry));
            } on TypeError {
              damaged = true;
            } on ArgumentError {
              damaged = true;
            }
          }
        }
        final draft = ChatDraft(text: text, attachments: attachments);
        if (damaged) {
          if (draft.isEmpty) {
            throw const FormatException('No readable draft fields');
          }
          Logger(
            'chat.drafts',
          ).warning('Recovered part of draft ${p.basename(source.path)}');
        }
        return draft;
      } on EncryptionRecovery catch (error) {
        // Keep looking: another artifact may still be readable. The envelope
        // that failed is kept, so a returned key reopens it later.
        locked = error;
      } on FormatException catch (error, stack) {
        Logger(
          'chat.drafts',
        ).warning('Unreadable draft ${p.basename(source.path)}', error, stack);
      }
    }
    // Never report an empty draft when the key is the reason: that would let
    // an empty autosave erase data the user can still recover.
    if (locked != null) throw locked;
    return const ChatDraft();
  }

  Future<void> save(String key, ChatDraft draft) {
    final write = _writes.then((_) async {
      final file = await _file(key);
      final backup = File('${file.path}.bak');
      if (draft.isEmpty) {
        // Validate every recoverable envelope before discarding any of them.
        for (final source in _readCandidates(file)) {
          if (await source.exists()) await encryption.read(source);
        }
        await _deleteArtifacts(file);
        return;
      }
      if (await backup.exists()) await encryption.read(backup);
      await encryption.write(file, utf8.encode(jsonEncode(draft.toJson())));
      if (await backup.exists()) await backup.delete();
    });
    _writes = write.then((_) {}, onError: (Object _, StackTrace _) {});
    return write;
  }
}
