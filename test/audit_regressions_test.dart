import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/data/storage/gguf_metadata.dart';
import 'package:ondevice_llm/desktop/load_settings/analytical_estimate.dart';
import 'package:ondevice_llm/features/hosting/workspace_uploads.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/model_profiles_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/remote_probe_summary.dart';
import 'package:ondevice_llm/inference/remote/remote_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _UploadRequest implements HttpRequest {
  @override
  int get contentLength => WorkspaceUploads.maxFileBytes;
  @override
  Uri get uri => Uri.parse('/?name=file.bin');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CPU and absent GPU charge target, draft and cache to RAM', () {
    const metadata = GgufMetadata(
      version: 3,
      tensorCount: 1,
      blockCount: 2,
      headCount: 2,
      embeddingLength: 128,
    );
    for (final cpu in [true, false]) {
      final estimate = analyticalMemoryEstimate(
        metadata: metadata,
        weightsBytes: 1024 * 1024,
        draftBytes: 1024 * 1024,
        settings: InferenceSettings(
          backend: cpu ? GpuBackend.cpu : GpuBackend.auto,
          nGpuLayers: 999,
        ),
        hardware: cpu ? const {'vramTotalMb': 8192} : const {},
      );
      expect(estimate['gpuLayers'], 0);
      expect(estimate['vramNeedMb'], 0);
      expect(estimate['ramNeedMb'], greaterThan(2));
    }
  });

  test('swaFull expands SWA cells while preserving narrower head widths', () {
    const metadata = GgufMetadata(
      version: 3,
      tensorCount: 1,
      blockCount: 2,
      headCount: 2,
      kvHeadCount: 1,
      keyLength: 64,
      valueLength: 64,
      keyLengthSwa: 32,
      valueLengthSwa: 32,
      slidingWindow: 128,
      swaLayers: [true, false],
    );
    const settings = InferenceSettings(
      contextSize: 4096,
      kvCacheType: KvCacheType.fp16,
    );
    final bounded = kvCacheBytes(metadata, settings);
    final full = kvCacheBytes(metadata, settings.copyWith(swaFull: true));
    expect(full, 4096 * (32 + 32 + 64 + 64) * 2);
    expect(full, greaterThan(bounded));
  });

  test('an unavailable selected backend cannot charge another GPU to VRAM', () {
    final estimate = analyticalMemoryEstimate(
      weightsBytes: 1024 * 1024,
      settings: const InferenceSettings(backend: GpuBackend.cuda),
      hardware: const {
        'devices': [
          {'type': 'gpu', 'backend': 'Vulkan', 'totalMb': 8192},
        ],
      },
    );
    expect(estimate['gpuLayers'], 0);
    expect(estimate['vramNeedMb'], 0);
    expect(estimate['ramNeedMb'], 1);
  });

  test(
    'upload setup failures release both byte and slot reservations',
    () async {
      var attempts = 0;
      final uploads = WorkspaceUploads(
        createDirectory: () async {
          attempts++;
          throw const FileSystemException('disk full');
        },
      );
      for (var i = 0; i < 70; i++) {
        await expectLater(
          uploads.receive(_UploadRequest()),
          throwsA(isA<FileSystemException>()),
        );
      }
      expect(attempts, 70);
      await uploads.dispose();
    },
  );

  test(
    'early profile edits merge into initialized profiles and persist',
    () async {
      SharedPreferences.setMockInitialValues({
        'model_profiles_v1': jsonEncode({
          'saved': {'temperature': 0.4},
          'edited': {'topP': 0.8},
        }),
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final profiles = container.read(modelProfilesProvider.notifier);
      await Future.wait([
        profiles.setKey('edited', 'temperature', 0.3),
        profiles.setKey('edited', 'topK', 30),
      ]);
      expect(profiles.of('saved'), {'temperature': 0.4});
      expect(profiles.of('edited'), {
        'topP': 0.8,
        'temperature': 0.3,
        'topK': 30,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(
        jsonDecode(prefs.getString('model_profiles_v1')!),
        container.read(modelProfilesProvider),
      );
    },
  );

  test('probe summaries localize plurals, health and tools', () {
    for (final locale in ['en', 'fr', 'es']) {
      final t = stringsFor(locale);
      for (final count in [0, 1, 2]) {
        final report = RemoteServerReport(
          models: List.generate(count, (i) => RemoteModel('$i')),
          health: 'not advertised',
          tools: List.generate(count, (i) => '$i'),
        );
        final summary = remoteProbeSummary(t, report);
        expect(summary, contains(t.remoteProbeModels(count)));
        expect(summary, contains(t.remoteProbeNotAdvertised));
        expect(
          summary,
          contains(
            count == 0 ? t.remoteProbeNoTools : t.remoteProbeTools(count),
          ),
        );
        if (locale != 'en') expect(summary, isNot(contains('Connected')));
      }
      expect(
        remoteProbeSummary(
          t,
          const RemoteServerReport(
            models: [RemoteModel('one')],
            health: 'n/a',
            tools: [],
          ),
        ),
        t.remoteProbeModels(1),
      );
    }
  });
}
