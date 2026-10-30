import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/platform/desktop_host.dart';
import '../../core/platform/device_info.dart';
import 'model_folders.dart';
import 'gguf_split.dart';

class ModelStorage {
  static const _subdir = 'models';
  static const _channel = MethodChannel('ondevice_llm/storage');

  static Future<DeviceStorage?> availableStorage() async {
    if (!DesktopHost.active) return DeviceStorage.read();
    try {
      final available = await (await desktopFolders()).availableBytes(
        (await modelsDir()).path,
      );
      return DeviceStorage(totalBytes: 0, availableBytes: available);
    } on MissingPluginException {
      return null;
    }
  }

  /// GGUF models plus the voice files (ONNX models, token lists and the
  /// Kokoro archive, which is unpacked next to them), and the safetensors
  /// VAEs and ESRGAN upscaler of the desktop image and video models.
  static const fileExtensions = [
    '.gguf',
    '.onnx',
    '.txt',
    '.tar.bz2',
    '.safetensors',
    '.pth',
  ];

  static Future<Directory> modelsDir() async {
    if (DesktopHost.active) {
      final dir = (await desktopFolders()).current;
      await dir.create(recursive: true);
      return dir;
    }
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

  static Future<ModelFolders> desktopFolders() async => ModelFolders(
    Directory(p.join((await getApplicationSupportDirectory()).path, _subdir)),
    await SharedPreferences.getInstance(),
    (path) async => (await const MethodChannel(
      'ondevice_llm/desktop',
    ).invokeMethod<int>('availableBytes', path))!,
  );

  /// Manifests and unpacked voice directories follow retained roots too.
  static Future<String> resourcePath(String relativePath) async {
    if (p.isAbsolute(relativePath) ||
        p.split(p.normalize(relativePath)).contains('..')) {
      throw ArgumentError.value(relativePath, 'relativePath');
    }
    if (DesktopHost.active) {
      return (await desktopFolders()).resolvePath(relativePath);
    }
    return p.join((await modelsDir()).path, relativePath);
  }

  static Future<File> modelFile(String fileName) async {
    if (fileName != p.basename(fileName) ||
        fileName.contains('\\') ||
        fileName.contains('/') ||
        !fileExtensions.any(fileName.toLowerCase().endsWith)) {
      throw const FormatException('Choose a single .gguf filename.');
    }
    if (DesktopHost.active) {
      await modelsDir();
      return (await desktopFolders()).resolve(fileName);
    }
    final dir = await modelsDir();
    return File(p.join(dir.path, fileName));
  }

  static Future<bool> exists(String fileName) async =>
      (await modelFile(fileName)).existsSync();

  static Future<void> delete(String fileName) async {
    final f = await modelFile(fileName);
    for (final name in GgufSplit.parse(fileName)?.names ?? [fileName]) {
      final part = File(p.join(f.parent.path, name));
      if (await part.exists()) await part.delete();
    }
  }

  /// Removes the downloader's `<file>.part` for [fileName], if any.
  static Future<void> deletePartial(String fileName) async {
    final file = await modelFile(fileName);
    for (final name in GgufSplit.parse(fileName)?.names ?? [fileName]) {
      final part = File(p.join(file.parent.path, '$name.part'));
      if (await part.exists()) await part.delete();
    }
  }

  /// Canonical order even when the user picks a later shard. Validate the
  /// entire set before copying or adopting any of it.
  static Future<List<File>> ggufFilesBeside(String path) async {
    final file = File(path);
    final split = GgufSplit.parse(p.basename(path));
    final files = split == null
        ? [file]
        : [
            for (final name in split.names)
              File(p.join(file.parent.path, name)),
          ];
    for (final f in files) {
      if (!await f.exists()) {
        throw FormatException(
          'Missing split GGUF part: ${p.basename(f.path)}. '
          'Keep all parts together in the same folder.',
        );
      }
    }
    return files;
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
