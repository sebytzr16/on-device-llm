import 'package:shared_preferences/shared_preferences.dart';

import 'ocr_layout.dart';
import '../../../core/l10n/l10n.dart';

class ScanCancelled implements Exception {
  const ScanCancelled();
}

class OcrUnavailable implements Exception {
  static const notice =
      'Text recognition is unavailable. Check installed OCR languages in system settings.';
  const OcrUnavailable();
  @override
  String toString() => notice;
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

/// One page's embedded text layer, with [coverage] in characters per
/// square point of the page. A page number or running header scores near
/// zero; a real text layer scores far above [_minLayerCoverage].
class PageLayer {
  final String text;
  final double coverage;
  const PageLayer(this.text, {this.coverage = 0});
}

/// One page at a time, with real page numbers even after OCR skips/failures.
/// Callbacks make limits, quality disclosure and cancellation host-testable.
class PdfTextScanner {
  /// A text layer this thin is treated as scanned: headers and page numbers
  /// score near zero, a real text layer far above this.
  static const _minLayerCoverage = 0.0005; // characters per square point

  static Future<String> scan({
    required int pages,
    required Future<PageLayer> Function(int page) textLayer,
    required Future<OcrReading> Function(int page) recognize,
    required ScanOptions options,
    required int maxCharacters,
    String localeCode = '',
    bool Function()? cancelled,
    void Function(int page, int total)? progress,
  }) async {
    final t = stringsFor(localeCode);
    final output = StringBuffer();
    var scanned = 0, skipped = 0, unreadable = 0;
    var ocrUnavailable = false;
    for (var page = 1; page <= pages; page++) {
      if (cancelled?.call() == true) throw const ScanCancelled();
      progress?.call(page, pages);
      final layer = await textLayer(page);
      final layerText = layer.text.trim();
      var ocrText = '';
      String quality = '';
      final bool layerThin =
          layerText.isEmpty || layer.coverage < _minLayerCoverage;
      if (layerThin) {
        if (layerText.isNotEmpty && scanned == options.maxScannedPages) {
          // No OCR budget left: keep the thin text layer as-is.
        } else if (scanned == options.maxScannedPages) {
          skipped++;
          continue;
        } else {
          scanned++;
          try {
            final read = await recognize(page);
            ocrText = read.text.trim();
            if (ocrText.isNotEmpty) {
              quality =
                  ' (OCR; ${read.confidence == null ? t.documentScanConfidenceUnknown : t.documentScanConfidence('${(read.confidence! * 100).round()}')})';
            }
          } on OcrUnavailable {
            ocrUnavailable = true;
          } catch (_) {
            // OCR failed: fall back to the text layer alone.
          }
        }
      }
      if (cancelled?.call() == true) throw const ScanCancelled();
      var text = layerText;
      if (ocrText.isNotEmpty) {
        final layerLines = layerText.split('\n').map((l) => l.trim()).toSet();
        final additions = ocrText.split('\n').map((l) => l.trim());
        text =
            '$layerText\n${additions.where((l) => l.isNotEmpty && !layerLines.contains(l)).join('\n')}';
      }
      if (text.isEmpty) {
        unreadable++;
        continue;
      }
      output.writeln('--- Page $page$quality ---');
      output.writeln(text);
      if (output.length > maxCharacters) {
        output.writeln(t.documentScanTextLimit);
        break;
      }
    }
    if (output.isEmpty) {
      if (ocrUnavailable) {
        throw FormatException(t.documentOcrUnavailable);
      }
      throw FormatException(t.documentScanNoText);
    }
    if (skipped > 0) {
      output.writeln(
        t.documentScanOcrLimit('${options.maxScannedPages}', '$skipped'),
      );
    }
    if (ocrUnavailable) output.writeln('[${t.documentOcrUnavailable}]');
    if (unreadable > 0) {
      output.writeln(t.documentScanUnreadable('$unreadable'));
    }
    return output.toString();
  }
}
