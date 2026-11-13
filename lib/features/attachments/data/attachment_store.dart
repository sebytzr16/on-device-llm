import 'dart:io';
import '../../../core/storage/device_encryption.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/storage/app_directories.dart';
import '../../../core/l10n/l10n.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../domain/attachment.dart';
import '../domain/document_text.dart';
import '../domain/scan_options.dart';
import '../domain/image_decoder.dart';
import 'on_device_ocr.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

/// Brings a picked file into the app: copies it under the app's documents
/// directory, normalises photos to PNG at a size vision models accept, and
/// extracts document text on-device. Nothing is uploaded anywhere.
class AttachmentStore {
  /// Longest edge for photos handed to a vision model. Qwen3.5 and Gemma 4
  /// tile larger images into more tokens than a phone context should spend.
  static const maxImageEdge = 1536;

  /// Longest edge kept for OCR/rescan of an imported photo. The original is
  /// retained below this edge so small print stays readable; only truly huge
  /// images are downscaled, which keeps decode memory bounded.
  static const maxOcrEdge = 2400;
  static const maxDocumentBytes = 64 * 1024 * 1024;

  static const imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
    '.bmp',
    '.heic',
    '.heif',
    '.avif',
    '.tif',
    '.tiff',
  };

  static Future<Directory> directory() async {
    final base = await appDataDirectory();
    final dir = Directory(p.join(base.path, 'attachments'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static bool isImageName(String name) =>
      imageExtensions.contains(p.extension(name).toLowerCase());

  /// Keeps a picture made by the chat's generate_image tool next to the
  /// imported attachments and returns it as an image attachment.
  static Future<Attachment> saveGenerated(
    Uint8List png, {
    String name = 'picture.png',
  }) async {
    final id = const Uuid().v4();
    final dir = await directory();
    final file = File(p.join(dir.path, '$id.png'));
    await file.writeAsBytes(png, flush: true);
    return Attachment(
      id: id,
      kind: AttachmentKind.image,
      name: name,
      mime: 'image/png',
      path: file.path,
      sizeBytes: png.length,
    );
  }

  /// Imports a file from [sourcePath] (or [bytes] when the picker only gives
  /// bytes). Images become PNG; documents keep their bytes and gain [text].
  static Future<Attachment> import({
    required String name,
    String? sourcePath,
    Uint8List? bytes,
    String localeCode = '',
    bool deferProcessing = false,
    bool Function()? cancelled,
    void Function(int page, int total)? progress,
  }) async {
    if (cancelled?.call() == true) throw const ScanCancelled();
    final t = stringsFor(localeCode);
    final scanOptions = await ScanOptions.read();
    if (bytes == null && await File(sourcePath!).length() > maxDocumentBytes) {
      throw FormatException(t.documentTooLarge);
    }
    final data =
        bytes ?? await DeviceEncryption.instance.read(File(sourcePath!));
    if (data.length > maxDocumentBytes) {
      throw FormatException(t.documentTooLarge);
    }
    final id = const Uuid().v4();
    final dir = await directory();
    if (deferProcessing) {
      final file = File(
        p.join(dir.path, '$id${p.extension(name).toLowerCase()}'),
      );
      await DeviceEncryption.instance.write(file, data);
      return Attachment(
        id: id,
        kind: isImageName(name) || _looksLikeImage(data)
            ? AttachmentKind.image
            : AttachmentKind.document,
        name: name,
        mime: _mimeFor(name),
        path: file.path,
        sizeBytes: data.length,
      );
    }
    if (isImageName(name) || _looksLikeImage(data)) {
      // The stored file is the copy handed to a vision model. OCR reads the
      // bounded original instead, because downscaling before recognition
      // destroys the fine print OCR needs; that copy only has to outlive
      // recognition, so it lives in the temporary directory and is deleted
      // afterwards. One import therefore leaves exactly one file behind.
      final vision = await normaliseImage(data, localeCode: localeCode);
      final visionFile = File(p.join(dir.path, '$id-vision.png'));
      await DeviceEncryption.instance.write(visionFile, vision);
      final ocrSource = await normaliseImage(
        data,
        localeCode: localeCode,
        maxEdge: maxOcrEdge,
      );
      String? recognized;
      double? confidence;
      String? ocrNotice;
      File? ocrFile;
      try {
        final temp = await getTemporaryDirectory();
        ocrFile = File(p.join(temp.path, 'ocr-$id.png'));
        await ocrFile.writeAsBytes(ocrSource, flush: true);
        final read = await OnDeviceOcr.recognize(ocrFile.path, scanOptions);
        recognized = read.text.trim();
        confidence = read.confidence;
      } catch (error) {
        ocrNotice = error is OcrUnavailable
            ? t.documentOcrUnavailable
            : t.documentOcrFailed('$error');
      } finally {
        if (ocrFile != null && await ocrFile.exists()) {
          await ocrFile.delete();
        }
      }
      if (cancelled?.call() == true) {
        await visionFile.delete();
        throw const ScanCancelled();
      }
      return Attachment(
        id: id,
        kind: AttachmentKind.image,
        name: name,
        mime: 'image/png',
        path: visionFile.path,
        sizeBytes: vision.length,
        text: recognized == null || recognized.isEmpty ? null : recognized,
        ocrConfidence: confidence,
        error: ocrNotice,
      );
    }
    final file = File(
      p.join(dir.path, '$id${p.extension(name).toLowerCase()}'),
    );
    await DeviceEncryption.instance.write(file, data);
    String? text, error;
    try {
      text = (await DocumentText.extract(
        data,
        name,
        localeCode: localeCode,
        pdfText: (bytes) => pdfText(
          bytes,
          options: scanOptions,
          localeCode: localeCode,
          cancelled: cancelled,
          progress: progress,
        ),
      )).text;
      if (text.isEmpty) error = t.documentNoText;
    } on ScanCancelled {
      await file.delete();
      rethrow;
    } on FormatException catch (e) {
      error = e.message;
    } catch (e) {
      error = t.documentReadFailed('$e');
    }
    if (cancelled?.call() == true) {
      await file.delete();
      throw const ScanCancelled();
    }
    return Attachment(
      id: id,
      kind: AttachmentKind.document,
      name: name,
      mime: _mimeFor(name),
      path: file.path,
      sizeBytes: data.length,
      text: error == null ? text : null,
      error: error,
    );
  }

  static bool _looksLikeImage(Uint8List b) =>
      b.length > 12 &&
      ((b[0] == 0xFF && b[1] == 0xD8) || // JPEG
          (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E) || // PNG
          (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) || // GIF
          (b[0] == 0x52 &&
              b[1] == 0x49 &&
              b[8] == 0x57 &&
              b[9] == 0x45)); // WEBP

  /// Decodes with the platform codec (JPEG, PNG, WebP, GIF, HEIC on
  /// Android 9+), downsizes to [maxImageEdge], re-encodes as PNG — the one
  /// format both llama.cpp's stb loader and every server accept.
  static Future<Uint8List> normaliseImage(
    Uint8List data, {
    String localeCode = '',
    int maxEdge = maxImageEdge,
  }) async {
    return decodeAndBoundImage(
      data,
      maxEdge: maxEdge,
      errorMessage: stringsFor(localeCode).documentImageEncoding,
    );
  }

  /// Extract text layers first, then OCR pages with no text layer on-device.
  /// Limit scanned pages to avoid an accidental hours-long import.
  static Future<String> pdfText(
    Uint8List bytes, {
    ScanOptions? options,
    String localeCode = '',
    bool Function()? cancelled,
    void Function(int page, int total)? progress,
  }) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openData(bytes);
    try {
      final settings = options ?? await ScanOptions.read();
      return await PdfTextScanner.scan(
        pages: doc.pages.length,
        textLayer: (number) async {
          final page = doc.pages[number - 1];
          final text = (await page.loadText())?.fullText ?? '';
          return PageLayer(
            text,
            coverage:
                page.width.isFinite &&
                    page.height.isFinite &&
                    page.width > 0 &&
                    page.height > 0
                ? text.length / (page.width * page.height)
                : 0,
          );
        },
        recognize: (number) => _ocrPdfPage(doc.pages[number - 1], settings),
        options: settings,
        maxCharacters: DocumentText.maxChars,
        localeCode: localeCode,
        cancelled: cancelled,
        progress: progress,
      );
    } finally {
      await doc.dispose();
    }
  }

  static ({int width, int height}) pdfRasterSize(double width, double height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw FormatException(stringsFor('').documentPdfSize);
    }
    final scale = math.min(2.0, math.min(2000 / width, 2800 / height));
    return (
      width: (width * scale).round().clamp(1, 2000),
      height: (height * scale).round().clamp(1, 2800),
    );
  }

  static Future<OcrReading> _ocrPdfPage(
    PdfPage page,
    ScanOptions options,
  ) async {
    final size = pdfRasterSize(page.width, page.height);
    final rendered = await page.render(width: size.width, height: size.height);
    if (rendered == null) return const OcrReading('');
    File? temporary;
    try {
      final image = await rendered.createImage(pixelSizeThreshold: 2800);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) return const OcrReading('');
        final dir = await getTemporaryDirectory();
        temporary = File(p.join(dir.path, 'ocr-${const Uuid().v4()}.png'));
        await temporary.writeAsBytes(data.buffer.asUint8List(), flush: true);
        return await OnDeviceOcr.recognize(temporary.path, options);
      } finally {
        image.dispose();
      }
    } finally {
      rendered.dispose();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  static String _mimeFor(String name) => switch (p
      .extension(name)
      .toLowerCase()) {
    '.pdf' => 'application/pdf',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.pptx' =>
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.odt' => 'application/vnd.oasis.opendocument.text',
    '.odp' => 'application/vnd.oasis.opendocument.presentation',
    '.ods' => 'application/vnd.oasis.opendocument.spreadsheet',
    '.epub' => 'application/epub+zip',
    '.rtf' => 'application/rtf',
    '.html' || '.htm' => 'text/html',
    '.json' => 'application/json',
    '.csv' => 'text/csv',
    '.md' => 'text/markdown',
    _ => 'text/plain',
  };

  /// Only direct, non-symlink children belong to attachment storage.
  static Future<File?> ownedFile(String path) async {
    final dir = await directory();
    final absolute = p.normalize(p.absolute(path));
    if (p.dirname(absolute) != p.normalize(p.absolute(dir.path))) return null;
    if (await FileSystemEntity.type(absolute, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final file = File(absolute);
    final root = await dir.resolveSymbolicLinks();
    if (p.dirname(await file.resolveSymbolicLinks()) != root) return null;
    return file;
  }

  static Future<void> delete(Attachment a) async {
    try {
      final f = await ownedFile(a.path);
      if (f != null && await f.exists()) await f.delete();
    } catch (e, st) {
      quietFailure('attachment_store:335', e, st);
    }
  }
}
