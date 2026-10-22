import 'package:shared_preferences/shared_preferences.dart';

import 'ocr_layout.dart';

class ScanCancelled implements Exception {
  const ScanCancelled();
}

class ScanOptions {
  static const key = 'text_recognition_options_v1';
  static Future<void>? _pending;
  final String language;
  final int maxScannedPages;
  const ScanOptions({this.language = 'auto', this.maxScannedPages = 20});
  static const languages = ['auto', 'en', 'fr', 'es'];
  static const pageLimits = [20, 50, 100, 300];
  static Future<ScanOptions> read() async {
    await _pending;
    final prefs = await SharedPreferences.getInstance();
    final values = prefs.getStringList(key) ?? const [];
    return ScanOptions(
      language: values.isNotEmpty && languages.contains(values[0])
          ? values[0]
          : 'auto',
      maxScannedPages:
          values.length > 1 && pageLimits.contains(int.tryParse(values[1]))
          ? int.parse(values[1])
          : 20,
    );
  }

  Future<void> save() {
    final previous = _pending;
    final next = (() async {
      await previous;
      if (!languages.contains(language) ||
          !pageLimits.contains(maxScannedPages)) {
        throw const FormatException('Invalid scan options.');
      }
      if (!await (await SharedPreferences.getInstance()).setStringList(key, [
        language,
        '$maxScannedPages',
      ])) {
        throw StateError('Cannot save scan options.');
      }
    })();
    final settled = next.catchError((Object _) {});
    _pending = settled;
    settled.then((_) {
      if (identical(_pending, settled)) _pending = null;
    });
    return next;
  }
}

class OcrReading {
  final String text;
  final double? confidence;
  const OcrReading(this.text, {this.confidence});

  /// Uses the line boxes when the reply has them, so a receipt's amounts
  /// sit next to their labels; otherwise ML Kit's own text.
  static OcrReading fromJson(Map<String, dynamic> value) {
    final raw = value['confidence'];
    final boxes = value['lines'];
    final lines = boxes is List
        ? boxes.map(OcrLine.fromJson).nonNulls.toList()
        : const <OcrLine>[];
    final paired = boxes is List && lines.length == boxes.length
        ? OcrLayout.paired(lines)
        : null;
    return OcrReading(
      paired ?? (value['text'] is String ? value['text'] as String : ''),
      confidence: raw is num && raw.isFinite && raw >= 0 && raw <= 1
          ? raw.toDouble()
          : null,
    );
  }
}

/// One page at a time, with real page numbers even after OCR skips/failures.
/// Callbacks make limits, quality disclosure and cancellation host-testable.
class PdfTextScanner {
  static Future<String> scan({
    required int pages,
    required Future<String> Function(int page) textLayer,
    required Future<OcrReading> Function(int page) recognize,
    required ScanOptions options,
    required int maxCharacters,
    bool Function()? cancelled,
    void Function(int page, int total)? progress,
  }) async {
    final output = StringBuffer();
    var scanned = 0, skipped = 0, unreadable = 0;
    for (var page = 1; page <= pages; page++) {
      if (cancelled?.call() == true) throw const ScanCancelled();
      progress?.call(page, pages);
      var text = (await textLayer(page)).trim();
      String quality = '';
      if (text.isEmpty) {
        if (scanned == options.maxScannedPages) {
          skipped++;
          continue;
        }
        scanned++;
        try {
          final read = await recognize(page);
          text = read.text.trim();
          quality =
              ' (OCR; ${read.confidence == null ? 'confidence unavailable' : 'recognizer confidence ${(read.confidence! * 100).round()}%'}; review for errors)';
        } catch (_) {
          text = '';
        }
      }
      if (cancelled?.call() == true) throw const ScanCancelled();
      if (text.isEmpty) {
        unreadable++;
        continue;
      }
      output.writeln('--- Page $page$quality ---');
      output.writeln(text);
      if (output.length > maxCharacters) {
        output.writeln('[Text limit reached; later pages were not processed.]');
        break;
      }
    }
    if (output.isEmpty) {
      throw const FormatException(
        'No readable text was found. Try a clearer scan or attach page photos.',
      );
    }
    if (skipped > 0) {
      output.writeln(
        '[OCR limit ${options.maxScannedPages}: $skipped scanned pages skipped. Text layers were still read.]',
      );
    }
    if (unreadable > 0) {
      output.writeln('[$unreadable pages could not be read.]');
    }
    return output.toString();
  }
}
