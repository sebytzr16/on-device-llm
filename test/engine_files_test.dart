import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/desktop/engine_files.dart';
import 'package:ondevice_llm/desktop/engine_files_panel.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('engine-files-'));
  tearDown(() => dir.deleteSync(recursive: true));

  EngineFiles manifest(Map<String, List<int>> contents) => EngineFiles.parse(
    dir.path,
    jsonEncode({
      'version': 1,
      'files': [
        for (final e in contents.entries)
          {
            'name': e.key,
            'size': e.value.length,
            'sha256': sha256.convert(e.value).toString(),
          },
      ],
    }),
  );

  test(
    'missing manifest is unverified; malformed and unsafe manifests rejected',
    () {
      expect(EngineFiles.read(dir.path).state, EngineManifestState.unverified);
      expect(
        EngineFiles.parse(dir.path, '{').state,
        EngineManifestState.malformed,
      );
      expect(
        manifest({
          '../bad.dll': [1],
        }).state,
        EngineManifestState.malformed,
      );
      expect(
        manifest({
          'good.dll': [1],
        }).state,
        EngineManifestState.ready,
      );
      expect(EngineFiles.parse(dir.path, '{}').checkSizes(), isEmpty);
    },
  );

  test(
    'size check skips CUDA with missing companion before opening next bridge',
    () {
      final skipped = <String>[];
      final opened = <String>[];
      final selected = LlamaBindings.openWindowsLibrary<String>(
        skipped: skipped,
        open: (name) {
          opened.add(name);
          return name;
        },
        gpuDeviceCount: (_) => 1,
        environment: const {},
        fileExists: (_) => true,
        hasAvx2: () => true,
        hasAvx512: () => false,
        checkEngineFiles: (name) => name == 'ondevice_llm_cuda.dll'
            ? const [
                EngineFileResult('cudart64_13.dll', EngineFileStatus.missing),
              ]
            : const [],
      );
      expect(selected.name, 'ondevice_llm_cuda12.dll');
      expect(opened, ['ondevice_llm_cuda12.dll']);
      expect(skipped.single, contains('cudart64_13.dll (missing)'));
    },
  );

  test('companions stay with their CUDA runtime and bridge variant', () {
    expect(
      EngineFiles.companionOf('cudart64_13.dll', 'ondevice_llm_cuda.dll'),
      isTrue,
    );
    expect(
      EngineFiles.companionOf('cudart64_12.dll', 'ondevice_llm_cuda.dll'),
      isFalse,
    );
    expect(
      EngineFiles.companionOf('cublasLt64_12.dll', 'ondevice_llm_cuda12.dll'),
      isTrue,
    );
    expect(
      EngineFiles.companionOf('cudart64_13.dll', 'ondevice_llm.dll'),
      isFalse,
    );
    expect(
      EngineFiles.companionOf('ondevice_llm_vulkan.dll', 'ondevice_llm.dll'),
      isFalse,
    );
    expect(
      EngineFiles.companionOf('ggml-base.dll', 'ondevice_llm.dll'),
      isTrue,
    );
  });

  test(
    'full verification streams good, changed, missing and wrong size results',
    () async {
      final files = manifest({
        'good.dll': [1],
        'changed.dll': [1],
        'missing.dll': [1],
        'short.dll': [1, 2],
      });
      File('${dir.path}/good.dll').writeAsBytesSync([1]);
      File('${dir.path}/changed.dll').writeAsBytesSync([2]);
      File('${dir.path}/short.dll').writeAsBytesSync([1]);
      expect(files.checkSizes().map((r) => r.status), [
        EngineFileStatus.ok,
        EngineFileStatus.ok,
        EngineFileStatus.missing,
        EngineFileStatus.wrongSize,
      ]);
      final results = await files.verify().toList();
      expect(results.map((r) => r.status), [
        EngineFileStatus.ok,
        EngineFileStatus.changed,
        EngineFileStatus.missing,
        EngineFileStatus.wrongSize,
      ]);
    },
  );

  testWidgets('result list names failures and explains offline repair', (
    tester,
  ) async {
    final files = manifest({
      'good.dll': [1],
      'changed.dll': [1],
      'missing.dll': [1],
      'short.dll': [1, 2],
    });
    File('${dir.path}/good.dll').writeAsBytesSync([1]);
    File('${dir.path}/changed.dll').writeAsBytesSync([2]);
    File('${dir.path}/short.dll').writeAsBytesSync([1]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: EngineFilesPanel(read: () => files)),
      ),
    );
    await tester.tap(find.text('Verify engine files'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.text('good.dll: OK'), findsOneWidget);
    expect(find.text('changed.dll: Changed'), findsOneWidget);
    expect(find.text('missing.dll: Missing'), findsOneWidget);
    expect(find.text('short.dll: Wrong size'), findsOneWidget);
    expect(
      find.textContaining('Reinstalling the app restores them.'),
      findsOneWidget,
    );
  });

  testWidgets('missing manifest shows unverified without failure', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EngineFilesPanel(read: () => EngineFiles.read(dir.path)),
        ),
      ),
    );
    await tester.tap(find.text('Verify engine files'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unverified:'), findsOneWidget);
    expect(find.textContaining('Reinstalling'), findsNothing);
  });
}
