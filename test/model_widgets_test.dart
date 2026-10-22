import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/platform/device_info.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/storage/download_manager.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_card.dart';
import 'package:ondevice_llm/features/onboarding/presentation/widgets/starter_model.dart';

const _gb = 1024 * 1024 * 1024;
const _phone = DeviceMemory(
  totalBytes: (11.4 * _gb) ~/ 1,
  availableBytes: 6 * _gb,
  lowMemory: false,
);
final _qwen4b = bundledCatalog.singleWhere((m) => m.id == 'qwen35-4b-iq4nl');

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  testWidgets('idle card shows facts, fit and Download', (tester) async {
    await tester.pumpWidget(_host(ModelCard(model: _qwen4b, memory: _phone)));
    for (final t in [
      'Qwen3.5 4B',
      '4B',
      'IQ4_NL',
      '2.40 GB',
      'Reasoning',
      'Fits this phone',
      'License · Apache-2.0',
      'Download',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text(catalogMeta['qwen35-4b-iq4nl']!.blurb), findsOneWidget);
    expect(find.text('Active'), findsNothing);
  });

  testWidgets('downloading card shows percent, speed and Pause', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ModelCard(
          model: _qwen4b,
          memory: _phone,
          progress: DownloadProgress(
            modelId: _qwen4b.id,
            status: DownloadStatus.downloading,
            received: 420,
            total: 1000,
            bytesPerSecond: 12.3 * 1048576,
          ),
        ),
      ),
    );
    expect(find.text('42.0%  ·  12.3 MB/s'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('verifying card shows SHA-256 line', (tester) async {
    await tester.pumpWidget(
      _host(
        ModelCard(
          model: _qwen4b,
          progress: DownloadProgress(
            modelId: _qwen4b.id,
            status: DownloadStatus.verifying,
          ),
        ),
      ),
    );
    expect(find.text('Verifying SHA-256…'), findsOneWidget);
    expect(find.text('Verifying…'), findsOneWidget);
  });

  testWidgets('failed card offers Resume / retry with error in view', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ModelCard(
          model: _qwen4b,
          progress: DownloadProgress(
            modelId: _qwen4b.id,
            status: DownloadStatus.failed,
            error: 'Connection lost',
          ),
        ),
      ),
    );
    expect(find.text('Resume / retry'), findsOneWidget);
    expect(find.text('Connection lost'), findsOneWidget);
  });

  testWidgets('the active card offers Unload instead of Use model', (
    tester,
  ) async {
    final downloaded = _qwen4b.copyWith(
      isDownloaded: true,
      localPath: '/m.gguf',
    );
    var unloaded = 0;
    await tester.pumpWidget(
      _host(
        ModelCard(
          model: downloaded,
          memory: _phone,
          active: true,
          onLoad: () {},
          onUnload: () => unloaded++,
          onDelete: () {},
        ),
      ),
    );
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Use model'), findsNothing);
    expect(find.text('Remove'), findsOneWidget);
    await tester.tap(find.byKey(Key('unload-${downloaded.id}')));
    expect(unloaded, 1);
  });

  test('starter recommendation follows RAM tiers', () {
    DeviceMemory mem(double gb) => DeviceMemory(
      totalBytes: (gb * _gb).round(),
      availableBytes: 0,
      lowMemory: false,
    );
    expect(recommendStarter(mem(11.4), bundledCatalog).id, 'qwen35-4b-iq4nl');
    expect(recommendStarter(mem(6), bundledCatalog).id, 'qwen35-2b-iq4nl');
    expect(recommendStarter(mem(4), bundledCatalog).id, 'qwen35-0.8b-q8_0');
    expect(recommendStarter(null, bundledCatalog).id, 'qwen35-0.8b-q8_0');
    final alts = starterAlternatives(
      mem(11.4),
      bundledCatalog,
      recommendStarter(mem(11.4), bundledCatalog),
    );
    expect(alts.any((m) => m.id == 'smollm2-135m-q4km'), isFalse);
    expect(alts.any((m) => m.id == 'qwen35-4b-iq4nl'), isFalse);
  });
}
