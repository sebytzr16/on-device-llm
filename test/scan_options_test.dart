import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/attachments/domain/scan_options.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('unavailable OCR is disclosed for scanned and mixed PDFs', () async {
    Future<String> scan(bool mixed) => PdfTextScanner.scan(
      pages: 2,
      textLayer: (page) async => PageLayer(
        mixed && page == 1 ? 'Existing text' : '',
        coverage: mixed && page == 1 ? 0.00001 : 0,
      ),
      recognize: (_) async => throw const OcrUnavailable(),
      options: const ScanOptions(),
      maxCharacters: 10000,
    );
    await expectLater(
      scan(false),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'notice',
          OcrUnavailable.notice,
        ),
      ),
    );
    final mixed = await scan(true);
    expect(mixed, contains('Existing text'));
    expect(mixed, contains(OcrUnavailable.notice));
  });
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
        textLayer: (p) async => PageLayer(
          p == 24 ? 'Late text layer' : '',
          coverage: p == 24 ? 0.00001 : 0,
        ),
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
        textLayer: (p) async => const PageLayer(''),
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
          textLayer: (_) async => const PageLayer(''),
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
        textLayer: (_) async => const PageLayer(''),
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

  test(
    'a sparse text layer is still OCRd and both layers are kept (A06)',
    () async {
      var recognizes = 0;
      final result = await PdfTextScanner.scan(
        pages: 2,
        textLayer: (page) async => PageLayer(
          page == 1 ? 'Page 1' : 'A full page of body text. ' * 30,
          coverage: page == 1 ? 0.00001 : 0.02,
        ),
        recognize: (page) async {
          recognizes++;
          return OcrReading('OCR text of page $page', confidence: 0.9);
        },
        options: const ScanOptions(),
        maxCharacters: 10000,
      );
      // Page 1 carries a text layer, but it covers almost nothing: OCR runs.
      expect(recognizes, 1);
      // Both layers survive, with page provenance.
      expect(
        result,
        contains('--- Page 1 (OCR; recognizer confidence 90%) ---'),
      );
      expect(result, contains('Page 1\nOCR text of page 1'));
      expect(result, contains('A full page of body text.'));
      // Page 2's layer is complete: no OCR and no quality notice.
      expect(result, isNot(contains('OCR text of page 2')));
      expect(result, isNot(contains('Page 2 (OCR')));
    },
  );

  test(
    'a thin text layer is kept even when the OCR limit is reached (A06)',
    () async {
      var recognizes = 0;
      final result = await PdfTextScanner.scan(
        pages: 3,
        textLayer: (page) async => PageLayer('Header $page', coverage: 0.00001),
        recognize: (page) async {
          recognizes++;
          return OcrReading('OCR page $page');
        },
        options: const ScanOptions(maxScannedPages: 1),
        maxCharacters: 10000,
      );
      expect(recognizes, 1);
      expect(result, contains('Page 1 (OCR; confidence unavailable)'));
      expect(result, contains('Header 1\nOCR page 1'));
      expect(result, contains('--- Page 2 ---\nHeader 2'));
      expect(result, contains('--- Page 3 ---\nHeader 3'));
      expect(result, isNot(contains('OCR limit')));
    },
  );
}
