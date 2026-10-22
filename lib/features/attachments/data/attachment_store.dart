import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../domain/attachment.dart';
import '../domain/document_text.dart';
import '../domain/scan_options.dart';
import 'on_device_ocr.dart';

/// Brings a picked file into the app: copies it under the app's documents
/// directory, normalises photos to PNG at a size vision models accept, and
/// extracts document text on-device. Nothing is uploaded anywhere.
class AttachmentStore {
  /// Longest edge for photos handed to a vision model. Qwen3.5 and Gemma 4
  /// tile larger images into more tokens than a phone context should spend.
  static const maxImageEdge = 1536;
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
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'attachments'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static bool isImageName(String name) =>
      imageExtensions.contains(p.extension(name).toLowerCase());

  /// Imports a file from [sourcePath] (or [bytes] when the picker only gives
  /// bytes). Images become PNG; documents keep their bytes and gain [text].
  static Future<Attachment> import({
    required String name,
    String? sourcePath,
    Uint8List? bytes,
    bool Function()? cancelled,
    void Function(int page, int total)? progress,
  }) async {
    if (cancelled?.call() == true) throw const ScanCancelled();
    final scanOptions = await ScanOptions.read();
    if (bytes == null && await File(sourcePath!).length() > maxDocumentBytes) {
      throw const FormatException('File is larger than 64 MB.');
    }
    final data = bytes ?? await File(sourcePath!).readAsBytes();
    if (data.length > maxDocumentBytes) {
      throw const FormatException('File is larger than 64 MB.');
    }
    final id = const Uuid().v4();
    final dir = await directory();
    if (isImageName(name) || _looksLikeImage(data)) {
      final png = await normaliseImage(data);
      final file = File(p.join(dir.path, '$id.png'));
      await file.writeAsBytes(png, flush: true);
      String? recognized;
      double? confidence;
      try {
        final read = await OnDeviceOcr.recognize(file.path, scanOptions);
        recognized = read.text.trim();
        confidence = read.confidence;
      } catch (_) {
        // The original photo remains available to a vision model if OCR fails.
      }
      if (cancelled?.call() == true) {
        await file.delete();
        throw const ScanCancelled();
      }
      return Attachment(
        id: id,
        kind: AttachmentKind.image,
        name: name,
        mime: 'image/png',
        path: file.path,
        sizeBytes: png.length,
        text: recognized == null || recognized.isEmpty ? null : recognized,
        ocrConfidence: confidence,
      );
    }
    final file = File(
      p.join(dir.path, '$id${p.extension(name).toLowerCase()}'),
    );
    await file.writeAsBytes(data, flush: true);
    String? text, error;
    try {
      text = (await DocumentText.extract(
        data,
        name,
        pdfText: (bytes) => pdfText(
          bytes,
          options: scanOptions,
          cancelled: cancelled,
          progress: progress,
        ),
      )).text;
      if (text.isEmpty) error = 'No text found in this file.';
    } on ScanCancelled {
      await file.delete();
      rethrow;
    } on FormatException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Could not read this file: $e';
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
  static Future<Uint8List> normaliseImage(Uint8List data) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(data);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width, h = descriptor.height;
    final scale = w > h ? maxImageEdge / w : maxImageEdge / h;
    final codec = scale < 1
        ? await descriptor.instantiateCodec(
            targetWidth: (w * scale).round(),
            targetHeight: (h * scale).round(),
          )
        : await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    try {
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) {
        throw const FormatException('Image could not be encoded.');
      }
      return png.buffer.asUint8List();
    } finally {
      frame.image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  /// Extract text layers first, then OCR pages with no text layer on-device.
  /// Limit scanned pages to avoid an accidental hours-long import.
  static Future<String> pdfText(
    Uint8List bytes, {
    ScanOptions? options,
    bool Function()? cancelled,
    void Function(int page, int total)? progress,
  }) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openData(bytes);
    try {
      final settings = options ?? await ScanOptions.read();
      return await PdfTextScanner.scan(
        pages: doc.pages.length,
        textLayer: (number) async =>
            (await doc.pages[number - 1].loadText())?.fullText ?? '',
        recognize: (number) => _ocrPdfPage(doc.pages[number - 1], settings),
        options: settings,
        maxCharacters: DocumentText.maxChars,
        cancelled: cancelled,
        progress: progress,
      );
    } finally {
      await doc.dispose();
    }
  }

  static ({int width, int height}) pdfRasterSize(double width, double height) {
    if (!width.isFinite || !height.isFinite || width <= 0 || height <= 0) {
      throw const FormatException('Invalid PDF page size.');
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

  static Future<void> delete(Attachment a) async {
    try {
      final f = File(a.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
