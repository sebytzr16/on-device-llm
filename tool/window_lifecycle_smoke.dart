// Release-only probe for Android window-owned models. The host closes and
// reopens this isolated app; no Dart disposal runs before Activity.onDestroy.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:path_provider/path_provider.dart';

final _container = ProviderContainer();

void _log(String marker, Object value) {
  // ignore: avoid_print
  print('$marker ${jsonEncode(value)}');
}

Future<void> _run() async {
  const path = String.fromEnvironment('BENCH_MODEL');
  const context = int.fromEnvironment('LIFECYCLE_CONTEXT', defaultValue: 4096);
  const settings = InferenceSettings(
    backend: GpuBackend.cpu,
    contextSize: context,
    maxTokens: 24,
    temperature: 0,
    thinkingModeEnabled: false,
    promptCache: false,
  );
  final external = await getExternalStorageDirectory();
  final modelPath = external == null
      ? path
      : '${external.path}/${path.split('/').last}';
  _log('LIFECYCLE_PROGRESS', {
    'providedPath': path,
    'resolvedPath': modelPath,
    'exists': await File(modelPath).exists(),
  });
  if (!await File(modelPath).exists()) {
    throw StateError('Missing test model: $modelPath');
  }
  final engine = _container.read(llamaEngineProvider);
  await engine.loadModel(modelPath: modelPath, settings: settings);
  final effective = engine.metrics['effectiveSettings'] as Map;
  final actualContext = (effective['contextSize'] as num).toInt();
  final trained = (effective['contextTrain'] as num).toInt();
  if (actualContext > settings.contextSize ||
      (trained > 0 && actualContext > trained)) {
    throw StateError('Context exceeded its request or trained length.');
  }
  final answer = await engine
      .generate(
        messages: const [
          {'role': 'user', 'content': 'Say hello in one sentence.'},
        ],
        fallbackTemplate: '',
        settings: settings,
      )
      .join();
  if (answer.trim().isEmpty) throw StateError('Generation was empty.');
  _log('LIFECYCLE_READY', {
    'rssBytes': ProcessInfo.currentRss,
    'effectiveSettings': effective,
    'nativeLibrary': engine.metrics['nativeLibrary'],
  });
  // Keep the model loaded. Activity destruction must release its owner.
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Window lifecycle release probe')),
      ),
    ),
  );
  unawaited(
    _run().catchError((Object error, StackTrace stack) {
      _log('LIFECYCLE_FAILED', {'error': '$error', 'stack': '$stack'});
    }),
  );
}
