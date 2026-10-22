import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/data/storage/model_storage.dart';
import 'package:ondevice_llm/data/storage/system_downloads.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:ondevice_llm/features/attachments/data/on_device_ocr.dart';
import 'package:ondevice_llm/features/attachments/domain/scan_options.dart';
import 'package:ondevice_llm/features/hosting/host_discovery.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<Uint8List> scanImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 1200, 1600),
    Paint()..color = Colors.white,
  );
  final painter = TextPainter(
    text: const TextSpan(
      text: 'ON DEVICE TEST\nBonjour le monde\nHola mundo\n12345',
      style: TextStyle(color: Colors.black, fontSize: 64),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 1100);
  painter.paint(canvas, const Offset(50, 150));
  painter.dispose();
  final image = await recorder.endRecording().toImage(1200, 1600);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Latin OCR and long scanned PDFs retain text and page limits',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('Native scan integration')),
        ),
      );
      final directory = await (await getTemporaryDirectory()).createTemp(
        'scan-platform-',
      );
      final bytes = await scanImage();
      final file = await File('${directory.path}/scan.png').writeAsBytes(bytes);
      try {
        final reading = await OnDeviceOcr.recognize(
          file.path,
          const ScanOptions(),
        );
        expect(reading.text, contains('ON DEVICE TEST'));
        expect(reading.text, contains('Bonjour'));
        expect(reading.text, contains('Hola'));
        if (reading.confidence != null) {
          expect(reading.confidence, inInclusiveRange(0, 1));
        }
        final pdf = pw.Document();
        final picture = pw.MemoryImage(bytes);
        for (var page = 0; page < 22; page++) {
          pdf.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (_) => pw.Image(picture),
            ),
          );
        }
        final pdfBytes = await pdf.save();
        final short = await AttachmentStore.pdfText(
          pdfBytes,
          options: const ScanOptions(),
        );
        expect(short, contains('Page 20 (OCR'));
        expect(short, contains('2 scanned pages skipped'));
        var reached = 0;
        final long = await AttachmentStore.pdfText(
          pdfBytes,
          options: const ScanOptions(maxScannedPages: 50),
          progress: (page, total) {
            reached = page;
            expect(total, 22);
          },
        );
        expect(reached, 22);
        expect(long, contains('Page 22 (OCR'));
        expect(long, isNot(contains('pages skipped')));
        var cancelled = false;
        await expectLater(
          AttachmentStore.pdfText(
            pdfBytes,
            cancelled: () => cancelled,
            progress: (page, _) {
              if (page == 2) cancelled = true;
            },
          ),
          throwsA(isA<ScanCancelled>()),
        );
        // ignore: avoid_print
        print('PLATFORM_OCR_OK pages=22 confidence=${reading.confidence}');
      } finally {
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'Android OS transfer verifies, reattaches and removes cancelled jobs',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('System download integration')),
        ),
      );
      expect(Platform.isAndroid, true);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = Uint8List.fromList([
        71,
        71,
        85,
        70,
        3,
        0,
        0,
        0,
        ...List.filled(512 * 1024, 42),
      ]);
      var requestCount = 0;
      final requests = server.listen((request) async {
        requestCount++;
        request.response.contentLength = bytes.length;
        try {
          for (var offset = 0; offset < bytes.length; offset += 8192) {
            request.response.add(
              bytes.sublist(offset, (offset + 8192).clamp(0, bytes.length)),
            );
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 40));
          }
        } catch (_) {
          // Cancellation closes the response while the synthetic server writes.
        } finally {
          await request.response.close();
        }
      });
      var manager = DownloadManager(
        pollInterval: const Duration(milliseconds: 100),
      );
      final id = 'platform-${DateTime.now().microsecondsSinceEpoch}';
      final name = '$id.gguf';
      final target = await ModelStorage.modelFile(name);
      try {
        await manager.download(
          modelId: id,
          url: 'http://127.0.0.1:${server.port}/model.gguf',
          fileName: name,
          expectedSha256: sha256.convert(bytes).toString(),
          expectedSize: bytes.length,
        );
        expect(await target.readAsBytes(), bytes);
        expect(await File('${target.path}.part').exists(), false);
        await target.delete();
        // Disposing the Dart owner must leave the native job available to a
        // new owner. Counting HTTP requests proves that adoption does not
        // silently start another transfer. Actual process death is separate.
        final beforeAdoption = requestCount;
        final adopting = manager
            .progressStream(id)
            .firstWhere(
              (p) => p.received > 0 && p.status == DownloadStatus.downloading,
            )
            .timeout(const Duration(seconds: 30));
        final detached = expectLater(
          manager.download(
            modelId: id,
            url: 'http://127.0.0.1:${server.port}/model.gguf',
            fileName: name,
            expectedSha256: sha256.convert(bytes).toString(),
            expectedSize: bytes.length,
          ),
          throwsException,
        );
        await adopting;
        manager.dispose();
        await detached;
        expect(
          (await SystemDownloads.platform!.query(id)).status,
          isNot('failed'),
        );
        manager = DownloadManager(
          pollInterval: const Duration(milliseconds: 100),
        );
        await manager.download(
          modelId: id,
          url: 'http://127.0.0.1:${server.port}/model.gguf',
          fileName: name,
          expectedSha256: sha256.convert(bytes).toString(),
          expectedSize: bytes.length,
        );
        expect(requestCount, beforeAdoption + 1);
        expect(await target.readAsBytes(), bytes);
        await target.delete();
        await expectLater(
          manager.download(
            modelId: id,
            url: 'http://127.0.0.1:${server.port}/model.gguf',
            fileName: name,
            expectedSha256: '0' * 64,
            expectedSize: bytes.length,
          ),
          throwsException,
        );
        expect(await target.exists(), false);
        expect(await File('${target.path}.part').exists(), false);
        final began = manager
            .progressStream(id)
            .firstWhere(
              (p) => p.received > 0 && p.status == DownloadStatus.downloading,
            )
            .timeout(const Duration(seconds: 30));
        final stopped = expectLater(
          manager.download(
            modelId: id,
            url: 'http://127.0.0.1:${server.port}/model.gguf',
            fileName: name,
            expectedSha256: sha256.convert(bytes).toString(),
            expectedSize: bytes.length,
          ),
          throwsException,
        );
        await began;
        await manager.pause(id);
        await stopped;
        expect(await target.exists(), false);
        expect((await SystemDownloads.platform!.query(id)).status, 'failed');
        // ignore: avoid_print
        print('PLATFORM_DOWNLOAD_OK verified-adopted-rejected-and-cancelled');
      } finally {
        await manager.pause(id);
        manager.dispose();
        if (await target.exists()) await target.delete();
        final part = File('${target.path}.part');
        if (await part.exists()) await part.delete();
        await requests.cancel();
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('native discovery advertises and completes a bounded LAN scan', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('Nearby hosting integration')),
      ),
    );
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    final watch = Stopwatch()..start();
    try {
      await HostDiscovery.advertise(server.port);
      final hosts = await HostDiscovery.browse().timeout(
        const Duration(seconds: 12),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 12)));
      for (final host in hosts) {
        expect(Uri.parse(host.endpoint).scheme, 'http');
        expect(host.endpoint, isNot(contains('key=')));
      }
      // ignore: avoid_print
      print(
        'PLATFORM_DISCOVERY_OK hosts=${hosts.length} elapsedMs=${watch.elapsedMilliseconds}',
      );
    } finally {
      await HostDiscovery.stop();
      await server.close(force: true);
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}
