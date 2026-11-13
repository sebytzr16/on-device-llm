import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'device_encryption.dart';

/// libmtmd accepts filesystem paths. Plaintext copies exist only for the
/// lifetime of a native operation; persistent attachment paths stay encrypted.
class NativeMediaLease {
  NativeMediaLease._(this.messages, this._temporary);
  final List<Map<String, Object>> messages;
  final Directory? _temporary;

  static Future<NativeMediaLease> open(
    List<Map<String, Object>> messages, {
    DeviceEncryption? encryption,
    Future<Directory> Function()? temporaryDirectory,
  }) async {
    final cipher = encryption ?? DeviceEncryption.instance;
    final paths = <String, String>{};
    Directory? temporary;
    final out = <Map<String, Object>>[];
    try {
      for (final row in messages) {
        final images =
            (row['images'] as List?)?.cast<String>() ?? const <String>[];
        final mapped = <String>[];
        for (final path in images) {
          if (!paths.containsKey(path)) {
            final clear = await cipher.readEncrypted(File(path));
            if (clear == null) {
              paths[path] = path;
            } else {
              temporary ??=
                  await (await (temporaryDirectory ?? getTemporaryDirectory)())
                      .createTemp('native-media-');
              final file = File(
                p.join(temporary.path, '${paths.length}${p.extension(path)}'),
              );
              await file.writeAsBytes(clear, flush: true);
              paths[path] = file.path;
            }
          }
          mapped.add(paths[path]!);
        }
        out.add({...row, if (images.isNotEmpty) 'images': mapped});
      }
      return NativeMediaLease._(out, temporary);
    } catch (_) {
      if (temporary != null) await temporary.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> dispose() async {
    if (_temporary != null && await _temporary.exists()) {
      await _temporary.delete(recursive: true);
    }
  }
}
