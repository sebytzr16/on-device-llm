import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/features/knowledge/knowledge_embedder.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_catalog.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailedEngine extends LlamaEngine {
  int attempts = 0;
  @override
  Future<void> loadEmbedder({
    required String modelPath,
    String? mmprojPath,
    int threads = 4,
    int contextSize = 2048,
    InferenceSettings? placement,
  }) async {
    attempts++;
    throw const ModelLoadException('Not enough free memory for this model');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'failed embedding loads use lexical fallback until memory changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'embedder-cooldown-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
      final engine = _FailedEngine();
      final embedder = LlamaEmbedder(engine, embeddingModel, () async => true);
      final revision = LlamaEngine.memoryRevision;
      addTearDown(() async {
        embedder.dispose();
        engine.dispose();
        LlamaEngine.memoryRevision = revision;
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
      expect(await embedder.embedQueries(['first question']), isNull);
      expect(engine.attempts, 1);
      expect(await embedder.embedQueries(['second question']), isNull);
      await embedder.warm();
      expect(engine.attempts, 1);
      LlamaEngine.memoryRevision++;
      expect(await embedder.embedQueries(['after chat reload']), isNull);
      expect(engine.attempts, 2);
    },
  );

  test(
    'a failure keeps its reason, and a model that arrives is tried at once',
    () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp(
        'embedder-cooldown-',
      );
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => directory.path);
      final engine = _FailedEngine();
      var available = true;
      final embedder = LlamaEmbedder(
        engine,
        embeddingModel,
        () async => available,
      );
      final revision = LlamaEngine.memoryRevision;
      addTearDown(() async {
        embedder.dispose();
        engine.dispose();
        LlamaEngine.memoryRevision = revision;
        messenger.setMockMethodCallHandler(channel, null);
        await directory.delete(recursive: true);
      });
      expect(await embedder.embedQueries(['first question']), isNull);
      expect(engine.attempts, 1);
      // The real reason is kept for the index, not "not downloaded".
      expect(embedder.loadFailure, isA<ModelLoadException>());
      // The backoff holds while nothing changed.
      expect(await embedder.embedQueries(['second question']), isNull);
      expect(engine.attempts, 1);
      // A model that was missing and is now there is tried at once: the
      // backoff waits for memory to change, not for a download.
      available = false;
      expect(await embedder.embedQueries(['third question']), isNull);
      expect(embedder.loadFailure, isNull);
      available = true;
      expect(await embedder.embedQueries(['fourth question']), isNull);
      expect(engine.attempts, 2);
    },
  );
}
