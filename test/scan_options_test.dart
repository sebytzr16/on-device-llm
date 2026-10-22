import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/attachments/domain/scan_options.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('tall scanned pages preserve aspect ratio inside raster limits', () {
    final size = AttachmentStore.pdfRasterSize(1000, 6000);
    expect(size.height / size.width, closeTo(6, .02));
    expect(size.width, lessThanOrEqualTo(2000));
    expect(size.height, lessThanOrEqualTo(2800));
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'rapid scan edits persist in order and reads wait for the last edit',
    () async {
      final first = const ScanOptions(
        language: 'fr',
        maxScannedPages: 50,
      ).save();
      final second = const ScanOptions(
        language: 'es',
        maxScannedPages: 300,
      ).save();
      final latest = await ScanOptions.read();
      await Future.wait([first, second]);
      expect(latest.language, 'es');
      expect(latest.maxScannedPages, 300);
      await expectLater(
        const ScanOptions(maxScannedPages: -1).save(),
        throwsFormatException,
      );
      expect((await ScanOptions.read()).maxScannedPages, 300);
    },
  );
  test(
    'scan preferences persist; invalid saved values retain bounded defaults',
    () async {
      await const ScanOptions(language: 'fr', maxScannedPages: 100).save();
      expect((await ScanOptions.read()).maxScannedPages, 100);
      expect((await ScanOptions.read()).language, 'fr');
      await (await SharedPreferences.getInstance()).setStringList(
        ScanOptions.key,
        ['unknown', '-1'],
      );
      expect((await ScanOptions.read()).maxScannedPages, 20);
      expect((await ScanOptions.read()).language, 'auto');
    },
  );
  test(
    'long scans retain page provenance, confidence, skips and later text layers',
    () async {
      var calls = 0;
      final result = await PdfTextScanner.scan(
        pages: 24,
        textLayer: (p) async => p == 24 ? 'Late text layer' : '',
        recognize: (p) async {
          calls++;
          return const OcrReading('Scanned text', confidence: .65);
        },
        options: const ScanOptions(),
        maxCharacters: 100000,
      );
      expect(calls, 20);
      expect(result, contains('Page 20 (OCR; recognizer confidence 65%'));
      expect(result, contains('Page 24 ---\nLate text layer'));
      expect(result, contains('3 scanned pages skipped'));
      final long = await PdfTextScanner.scan(
        pages: 24,
        textLayer: (p) async => '',
        recognize: (p) async => OcrReading('Page $p'),
        options: const ScanOptions(maxScannedPages: 50),
        maxCharacters: 100000,
      );
      expect(long, contains('Page 24 (OCR; confidence unavailable'));
      expect(long, isNot(contains('skipped')));
    },
  );
  test(
    'cancellation stops before another page; exactly 20 pages are not labeled truncated',
    () async {
      var cancelled = false, calls = 0;
      await expectLater(
        PdfTextScanner.scan(
          pages: 3,
          textLayer: (_) async => '',
          recognize: (_) async {
            calls++;
            cancelled = true;
            return const OcrReading('text');
          },
          options: const ScanOptions(),
          maxCharacters: 10000,
          cancelled: () => cancelled,
        ),
        throwsA(isA<ScanCancelled>()),
      );
      expect(calls, 1);
      final result = await PdfTextScanner.scan(
        pages: 20,
        textLayer: (_) async => '',
        recognize: (_) async => const OcrReading('text'),
        options: const ScanOptions(),
        maxCharacters: 100000,
      );
      expect(result, isNot(contains('limit')));
    },
  );
  test('invalid recognizer confidence is unavailable, never invented', () {
    expect(
      OcrReading.fromJson({
        'text': 'text',
        'confidence': double.nan,
      }).confidence,
      isNull,
    );
    expect(
      OcrReading.fromJson({'text': 'text', 'confidence': 1.5}).confidence,
      isNull,
    );
    expect(OcrReading.fromJson({'text': 'text'}).confidence, isNull);
  });
}
