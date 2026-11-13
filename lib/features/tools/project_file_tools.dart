import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'domain/tool_spec.dart';

// Regex evaluation runs in a killable isolate so a pathological pattern cannot
// freeze the chat UI. Inputs and outputs remain bounded.
void _grepWorker((SendPort, String, String) input) {
  try {
    final regex = RegExp(input.$3);
    final matches = <(int, String)>[];
    final lines = input.$2.split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (regex.hasMatch(lines[i])) {
        matches.add((
          i + 1,
          lines[i].substring(0, lines[i].length.clamp(0, 500)),
        ));
        if (matches.length == 200) break;
      }
    }
    input.$1.send(matches);
  } catch (error) {
    input.$1.send(error.toString());
  }
}

/// One reviewable mutation. Approval never writes: the service revalidates first.
class FileChange {
  final String path;
  final String? before;
  final String after;
  final answer = Completer<bool>();
  bool applied = false, undone = false;
  Future<void> Function()? undo;
  FileChange(this.path, this.before, this.after);
  String get diff => [
    '--- $path',
    '+++ $path',
    ...?(before?.split('\n').map((s) => '- $s')),
    ...after.split('\n').map((s) => '+ $s'),
  ].join('\n');
}

class ProjectFileTools {
  static const maxBytes = 256 * 1024;
  static const maxEntries = 1000;
  final String folder;
  final Future<Directory> Function() backupDirectory;
  final Future<bool> Function(FileChange) approve;
  final bool Function() permitted;
  final void Function(FileChange)? changed;
  Future<void> _pending = Future.value();
  ProjectFileTools({
    required this.folder,
    required this.backupDirectory,
    required this.approve,
    required this.permitted,
    this.changed,
  });

  static final specs = <ToolSpec>[
    for (final name in [
      'list_files',
      'read_file',
      'search_files',
      'write_file',
      'edit_file',
    ])
      ToolSpec(
        name: name,
        description: switch (name) {
          'list_files' =>
            'List up to 1000 project files recursively. Optional path and glob (*, **, ?).',
          'read_file' =>
            'Read UTF-8 text, up to 256 KB. Optional 1-based inclusive start_line/end_line.',
          'search_files' =>
            'Search project text with a regex pattern (literal when regex=false). Capped at 200 matches. Optional glob.',
          'write_file' =>
            'Create or overwrite a project text file after user approval.',
          _ =>
            'Replace exactly one occurrence of nonempty old_text with new_text after user approval.',
        },
        parameters: {
          'type': 'object',
          'properties': {
            if (name != 'search_files')
              'path': {
                'type': 'string',
                'description': 'Relative to the project folder.',
              },
            if (name == 'list_files' || name == 'search_files')
              'glob': {'type': 'string'},
            if (name == 'search_files') ...{
              'pattern': {'type': 'string'},
              'regex': {'type': 'boolean'},
            },
            if (name == 'read_file') ...{
              'start_line': {'type': 'integer'},
              'end_line': {'type': 'integer'},
            },
            if (name == 'write_file') 'content': {'type': 'string'},
            if (name == 'edit_file') ...{
              'old_text': {'type': 'string'},
              'new_text': {'type': 'string'},
            },
          },
          'required': switch (name) {
            'read_file' => ['path'],
            'write_file' => ['path', 'content'],
            'edit_file' => ['path', 'old_text', 'new_text'],
            'search_files' => ['pattern'],
            _ => <String>[],
          },
        },
      ),
  ];

  void _check() {
    if (!permitted()) throw StateError('File access is no longer available.');
  }

  bool _inside(String root, String target) =>
      p.equals(root, target) || p.isWithin(root, target);

  /// Walk every existing component; never allow an escaping link, even if a
  /// later '..' could lead back inside. Missing parents are resolved recursively.
  Future<String> resolve(
    String relative, {
    bool write = false,
    bool checkAccess = true,
  }) async {
    if (checkAccess) _check();
    if (!p.isAbsolute(folder) ||
        folder.startsWith(r'\\') ||
        folder.startsWith('//')) {
      throw const FormatException(
        'Project folder must be an absolute local path.',
      );
    }
    if (relative.contains(':') ||
        relative.contains('\u0000') ||
        relative.startsWith('/') ||
        relative.startsWith('\\') ||
        p.isAbsolute(relative) ||
        p.windows.isAbsolute(relative)) {
      throw const FormatException('Only relative project paths are allowed.');
    }
    final root = await Directory(folder).resolveSymbolicLinks();
    if (root.startsWith(r'\\') || root.startsWith('//')) {
      throw const FormatException(
        'Network and device folders are not allowed.',
      );
    }
    var current = root;
    for (final part in relative.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') continue;
      final deviceName = part.split('.').first.trimRight();
      if (RegExp(
        r'^(con|prn|aux|nul|conin\$|conout\$|com[1-9]|lpt[1-9])$',
        caseSensitive: false,
      ).hasMatch(deviceName)) {
        throw const FormatException('Device paths are not allowed.');
      }
      if (write &&
          (part.toLowerCase() == '.git' ||
              part.endsWith('.') ||
              part.endsWith(' '))) {
        throw const FormatException('Protected or invalid write path.');
      }
      current = p.normalize(p.join(current, part));
      if (!_inside(root, current)) {
        throw const FormatException('Path escapes project folder.');
      }
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type != FileSystemEntityType.notFound) {
        current = await File(current).resolveSymbolicLinks();
        if (!_inside(root, current)) {
          throw const FormatException('Path escapes project folder.');
        }
        if (write &&
            p
                .split(p.relative(current, from: root))
                .any((s) => s.toLowerCase() == '.git')) {
          throw const FormatException('Cannot write .git internals.');
        }
      }
    }
    return current;
  }

  RegExp _glob(String glob) {
    final out = StringBuffer('^');
    for (var i = 0; i < glob.length; i++) {
      final c = glob[i];
      if (c == '*' && i + 1 < glob.length && glob[i + 1] == '*') {
        i++;
        if (i + 1 < glob.length && glob[i + 1] == '/') {
          i++;
          out.write('(?:.*/)?');
        } else {
          out.write('.*');
        }
      } else {
        out.write(
          c == '*'
              ? '[^/]*'
              : c == '?'
              ? '[^/]'
              : RegExp.escape(c),
        );
      }
    }
    return RegExp('$out\$');
  }

  Future<List<String>> _files(String path, String? glob) async {
    final start = await resolve(path);
    final root = await Directory(folder).resolveSymbolicLinks();
    final result = <String>[];
    final queue = <String>[start];
    var visited = 0;
    final filter = glob == null ? null : _glob(glob);
    while (queue.isNotEmpty && visited < maxEntries) {
      final dir = queue.removeLast();
      await for (final entry in Directory(dir).list(followLinks: false)) {
        if (++visited > maxEntries) break;
        final rel = p.relative(entry.path, from: root).replaceAll('\\', '/');
        if (p.basename(entry.path).toLowerCase() == '.git') continue;
        // Recheck each directory before traversal; don't follow directory links.
        if (entry is Link) continue;
        final safe = await resolve(rel);
        if (entry is Directory) {
          queue.add(safe);
        } else if (entry is File && (filter == null || filter.hasMatch(rel))) {
          result.add(rel);
        }
      }
    }
    result.sort();
    return result;
  }

  Future<String> _text(String path, {int start = 1, int? end}) async {
    if (start < 1 || (end != null && end < start)) {
      throw const FormatException('Invalid line range.');
    }
    final file = File(path);
    // Ranges can read further into large files, while bounding scanned input.
    if (start == 1 && end == null && await file.length() > maxBytes) {
      throw const FormatException('File exceeds 256 KB; request a line range.');
    }
    var scanned = 0, selected = 0, line = 0;
    final out = <String>[];
    final stream = file
        .openRead()
        .map((bytes) {
          scanned += bytes.length;
          if (scanned > 16 * 1024 * 1024) {
            throw const FormatException('Scan limit exceeded.');
          }
          if (bytes.contains(0)) {
            throw const FormatException('Binary files cannot be read.');
          }
          return bytes;
        })
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    try {
      await for (final text in stream) {
        line++;
        if (line >= start) {
          selected += utf8.encode(text).length + 1;
          if (selected > maxBytes) {
            throw const FormatException(
              'Read exceeds 256 KB; use a smaller line range.',
            );
          }
          out.add(text);
        }
        if (end != null && line >= end) break;
      }
    } on FormatException catch (e) {
      if (e.message.contains('Invalid UTF-8')) {
        throw const FormatException('Binary or non-UTF-8 file cannot be read.');
      }
      rethrow;
    }
    return out.join('\n');
  }

  // Mutation snapshots must retain exact bytes, including line endings.
  Future<List<int>?> _bytes(String target) async {
    if (!await File(target).exists()) return null;
    if (await File(target).length() > maxBytes) {
      throw const FormatException('Overwrite limit is 256 KB.');
    }
    final bytes = await File(target)
        .openRead(0, maxBytes + 1)
        .fold<List<int>>(<int>[], (out, chunk) => out..addAll(chunk));
    if (bytes.length > maxBytes) {
      throw const FormatException('Overwrite limit is 256 KB.');
    }
    if (bytes.contains(0)) {
      throw const FormatException('Binary files cannot be edited.');
    }
    utf8.decode(bytes); // Refuse non-UTF-8 content before offering a mutation.
    return bytes;
  }

  Future<String?> _snapshot(String target) async {
    final bytes = await _bytes(target);
    return bytes == null ? null : utf8.decode(bytes);
  }

  Future<ToolResult> run(ToolCall call) async {
    final done = Completer<ToolResult>();
    _pending = _pending.then((_) async {
      final watch = Stopwatch()..start();
      try {
        done.complete(
          ToolResult(
            call: call,
            output: await _run(call),
            ok: true,
            elapsedMs: watch.elapsedMilliseconds,
          ),
        );
      } catch (e) {
        done.complete(
          ToolResult(
            call: call,
            output: 'Error: $e',
            ok: false,
            elapsedMs: watch.elapsedMilliseconds,
          ),
        );
      }
    });
    return done.future;
  }

  Future<String> _run(ToolCall call) async {
    _check();
    final a = call.args;
    String requiredText(String key) {
      if (a[key] is! String) throw FormatException('Missing $key.');
      return a[key] as String;
    }

    if (call.name == 'list_files') {
      final files = await _files(
        a['path'] as String? ?? '',
        a['glob'] as String?,
      );
      return '${files.join('\n')}\n[Listing limited to $maxEntries entries scanned]';
    }
    if (call.name == 'search_files') {
      final pattern = requiredText('pattern');
      if (pattern.length > 500) {
        throw const FormatException('Pattern too long.');
      }
      final expression = a['regex'] == false ? RegExp.escape(pattern) : pattern;
      final hits = <String>[];
      final budget = Stopwatch()..start();
      for (final name in await _files('', a['glob'] as String?)) {
        if (budget.elapsed > const Duration(seconds: 15)) {
          return '${hits.join('\n')}\n[Search time limit reached]';
        }
        String text;
        try {
          text = await _text(await resolve(name));
        } on FormatException {
          continue;
        }
        final port = ReceivePort();
        final worker = await Isolate.spawn(_grepWorker, (
          port.sendPort,
          text,
          expression,
        ));
        try {
          final result = await port.first.timeout(const Duration(seconds: 2));
          if (result is String) throw FormatException(result);
          for (final match in (result as List).cast<(int, String)>()) {
            hits.add('$name:${match.$1}: ${match.$2}');
            if (hits.length >= 200) {
              return '${hits.join('\n')}\n[200 match limit]';
            }
          }
        } on TimeoutException {
          throw const FormatException(
            'Search regex exceeded its time limit; use a simpler pattern or regex=false.',
          );
        } finally {
          worker.kill(priority: Isolate.immediate);
          port.close();
        }
      }
      return '${hits.join('\n')}\n[Search limited to $maxEntries entries scanned]';
    }
    final path = requiredText('path');
    if (call.name == 'read_file') {
      return _text(
        await resolve(path),
        start: a['start_line'] as int? ?? 1,
        end: a['end_line'] as int?,
      );
    }
    if (call.name != 'write_file' && call.name != 'edit_file') {
      throw StateError('Unknown file tool.');
    }
    final target = await resolve(path, write: true);
    final originalBytes = await _bytes(target);
    final before = originalBytes == null ? null : utf8.decode(originalBytes);
    String after;
    if (call.name == 'write_file') {
      after = requiredText('content');
    } else {
      final old = requiredText('old_text');
      if (before == null ||
          old.isEmpty ||
          !before.contains(old) ||
          before.indexOf(old, before.indexOf(old) + 1) >= 0) {
        throw const FormatException(
          'old_text must match exactly once in the existing file.',
        );
      }
      after = before.replaceFirst(old, requiredText('new_text'));
    }
    if (utf8.encode(after).length > maxBytes) {
      throw const FormatException('Write exceeds 256 KB.');
    }
    final change = FileChange(path, before, after);
    if (!await approve(change)) return 'The user rejected this change';
    _check();
    if (await resolve(path, write: true) != target ||
        await _snapshot(target) != before) {
      throw StateError(
        'File changed while awaiting approval. Request the change again.',
      );
    }
    final backups = await backupDirectory();
    await backups.create(recursive: true);
    final backup = File(p.join(backups.path, '${const Uuid().v4()}.bak'));
    if (originalBytes != null) {
      await backup.writeAsBytes(originalBytes, flush: true);
    }
    await Directory(p.dirname(target)).create(recursive: true);
    if (await resolve(path, write: true) != target ||
        await _snapshot(target) != before) {
      throw StateError('Path or file changed.');
    }
    await File(target).writeAsString(after, flush: true);
    change.applied = true;
    change.undo = () async {
      if (change.undone) return;
      if (await resolve(path, write: true, checkAccess: false) != target ||
          await _snapshot(target) != after) {
        throw StateError('File has changed since this edit; undo refused.');
      }
      if (before == null) {
        await File(target).delete();
      } else {
        await File(
          target,
        ).writeAsBytes(await backup.readAsBytes(), flush: true);
      }
      change.undone = true;
      changed?.call(change);
    };
    changed?.call(change);
    return 'Applied change to $path. The user can Undo it in chat.';
  }
}
