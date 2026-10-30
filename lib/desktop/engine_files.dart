import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// These hashes diagnose package damage; they do not establish authenticity.
enum EngineManifestState { ready, unverified, malformed }

enum EngineFileStatus { ok, missing, wrongSize, changed, unreadable }

class EngineFileEntry {
  final String name;
  final int size;
  final String sha256;
  const EngineFileEntry(this.name, this.size, this.sha256);
}

class EngineFileResult {
  final String name;
  final EngineFileStatus status;
  const EngineFileResult(this.name, this.status);
}

class EngineFiles {
  final String directory;
  final EngineManifestState state;
  final List<EngineFileEntry> files;
  const EngineFiles(this.directory, this.state, this.files);

  factory EngineFiles.parse(String directory, String? source) {
    if (source == null) {
      return EngineFiles(directory, EngineManifestState.unverified, const []);
    }
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      if (json['version'] != 1) throw const FormatException();
      final names = <String>{};
      final files = (json['files'] as List).map((item) {
        final name = item['name'] as String;
        final size = item['size'] as int;
        final hash = item['sha256'] as String;
        if (!RegExp(r'^[^/\\:]+\.dll$', caseSensitive: false).hasMatch(name) ||
            size < 0 ||
            !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
            !names.add(name.toLowerCase())) {
          throw const FormatException();
        }
        return EngineFileEntry(name, size, hash.toLowerCase());
      }).toList();
      if (files.isEmpty) throw const FormatException();
      return EngineFiles(
        directory,
        EngineManifestState.ready,
        List.unmodifiable(files),
      );
    } catch (_) {
      return EngineFiles(directory, EngineManifestState.malformed, const []);
    }
  }

  factory EngineFiles.read(String directory) {
    try {
      final file = File(p.join(directory, 'engine-manifest.json'));
      return EngineFiles.parse(
        directory,
        file.existsSync() ? file.readAsStringSync() : null,
      );
    } catch (_) {
      return EngineFiles(directory, EngineManifestState.malformed, const []);
    }
  }

  static EngineFiles besideExecutable() =>
      EngineFiles.read(p.dirname(Platform.resolvedExecutable));

  // CUDA runtimes belong only to their bridge; other DLLs are shared.
  static bool companionOf(String name, String bridge) {
    final n = name.toLowerCase();
    if (n.startsWith('ondevice_llm')) return n == bridge;
    if (n.startsWith('cudart') || n.startsWith('cublas')) {
      return bridge.contains('_cuda') &&
          (bridge.contains('_cuda12') == n.endsWith('_12.dll'));
    }
    if (n.startsWith('ggml-cuda')) return bridge.contains('_cuda');
    if (n.startsWith('ggml-vulkan')) return bridge.contains('_vulkan');
    return true;
  }

  List<EngineFileResult> checkSizes({String? bridge}) {
    if (state != EngineManifestState.ready) return const [];
    final results = <EngineFileResult>[];
    if (bridge != null && !files.any((f) => f.name.toLowerCase() == bridge)) {
      results.add(EngineFileResult(bridge, EngineFileStatus.missing));
    }
    for (final entry in files) {
      if (bridge != null && !companionOf(entry.name, bridge)) continue;
      results.add(EngineFileResult(entry.name, _sizeStatus(entry)));
    }
    return results;
  }

  EngineFileStatus _sizeStatus(EngineFileEntry entry) {
    try {
      final stat = File(p.join(directory, entry.name)).statSync();
      if (stat.type == FileSystemEntityType.notFound) {
        return EngineFileStatus.missing;
      }
      return stat.type == FileSystemEntityType.file && stat.size == entry.size
          ? EngineFileStatus.ok
          : EngineFileStatus.wrongSize;
    } catch (_) {
      return EngineFileStatus.unreadable;
    }
  }

  List<EngineFileResult> checkVariant(String bridge) => checkSizes(
    bridge: bridge,
  ).where((r) => r.status != EngineFileStatus.ok).toList();

  // One worker owns all reads; only small result/progress messages reach the UI.
  Stream<EngineFileResult> verify() async* {
    if (state != EngineManifestState.ready) return;
    final port = ReceivePort();
    final worker = await Isolate.spawn(_verify, (this, port.sendPort));
    try {
      await for (final message in port) {
        if (message == null) break;
        yield message as EngineFileResult;
      }
    } finally {
      port.close();
      worker.kill(priority: Isolate.immediate);
    }
  }

  static Future<void> _verify((EngineFiles, SendPort) args) async {
    final (engine, port) = args;
    try {
      for (final entry in engine.files) {
        var status = engine._sizeStatus(entry);
        if (status == EngineFileStatus.ok) {
          try {
            final hash = await sha256
                .bind(File(p.join(engine.directory, entry.name)).openRead())
                .first;
            if (hash.toString() != entry.sha256) {
              status = EngineFileStatus.changed;
            }
          } catch (_) {
            status = EngineFileStatus.unreadable;
          }
        }
        port.send(EngineFileResult(entry.name, status));
      }
    } finally {
      port.send(null);
    }
  }
}
