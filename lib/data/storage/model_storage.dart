import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ModelStorage {
  static const _subdir = 'models';
  static const _channel = MethodChannel('ondevice_llm/storage');

  /// GGUF models plus the voice files (ONNX models, token lists and the
  /// Kokoro archive, which is unpacked next to them).
  static const fileExtensions = ['.gguf', '.onnx', '.txt', '.tar.bz2'];

  static Future<Directory> modelsDir() async {
    // path_provider.getExternalStorageDirectory() on Android maps to the
    // app-private getExternalFilesDir(), which is what the North Star wants.
    final base = Platform.isAndroid
        ? (await getExternalStorageDirectory()) ??
              await getApplicationSupportDirectory()
        : await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _subdir));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  static Future<File> modelFile(String fileName) async {
    if (fileName != p.basename(fileName) ||
        fileName.contains('\\') ||
        fileName.contains('/') ||
        !fileExtensions.any(fileName.toLowerCase().endsWith)) {
      throw const FormatException('Choose a single .gguf filename.');
    }
    final dir = await modelsDir();
    return File(p.join(dir.path, fileName));
  }

  static Future<bool> exists(String fileName) async =>
      (await modelFile(fileName)).existsSync();

  static Future<void> delete(String fileName) async {
    final f = await modelFile(fileName);
    if (f.existsSync()) await f.delete();
  }

  /// Removes the downloader's `<file>.part` for [fileName], if any.
  static Future<void> deletePartial(String fileName) async {
    final part = File('${(await modelFile(fileName)).path}.part');
    if (part.existsSync()) await part.delete();
  }

  /// Flags the file with NSURLIsExcludedFromBackupKey on iOS so multi-GB
  /// models are not uploaded to iCloud. Implemented on the Swift side.
  static Future<void> excludeFromICloud(File file) async {
    if (!Platform.isIOS) return;
    await _channel.invokeMethod('excludeFromBackup', {'path': file.path});
  }

  /// SHA-256 of [path]; a GGUF (any name not of another known kind, so a
  /// `.gguf.part` too) must also start with a valid header.
  static Future<String> validateAndHash(String path) => Isolate.run(() async {
    final file = File(path);
    final name = path.toLowerCase().replaceFirst(RegExp(r'\.part$'), '');
    if (fileExtensions.any((e) => e != '.gguf' && name.endsWith(e))) {
      return (await sha256.bind(file.openRead()).first).toString();
    }
    final handle = await file.open();
    try {
      final header = await handle.read(8);
      if (header.length != 8 ||
          header[0] != 71 ||
          header[1] != 71 ||
          header[2] != 85 ||
          header[3] != 70 ||
          header[4] < 2 ||
          header[4] > 3 ||
          header.skip(5).any((b) => b != 0)) {
        throw const FormatException(
          'Not a supported GGUF v2/v3 file. Select the actual model, not an HTML page or Git LFS pointer.',
        );
      }
    } finally {
      await handle.close();
    }
    return (await sha256.bind(file.openRead()).first).toString();
  });
}
