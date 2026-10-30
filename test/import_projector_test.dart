import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('import_projector'));
  tearDown(() => dir.deleteSync(recursive: true));

  File touch(String name) =>
      File(p.join(dir.path, name))..writeAsStringSync('x');

  test('the projector named like the model is paired on import', () {
    final model = touch('Gemma-4-E4B-it-Q8_0.gguf');
    touch('mmproj-Qwen3.5-4B-F16.gguf');
    final projector = touch('mmproj-Gemma-4-E4B-it-F16.gguf');
    expect(
      ModelManagerNotifier.projectorBeside(model.path)?.path,
      projector.path,
    );
  });

  test('the only projector in an LM Studio folder is paired', () {
    final model = touch('Gemma4-26B-A4B-Uncensored-Q4_K_M.gguf');
    final projector = touch('mmproj-model-BF16.gguf');
    expect(
      ModelManagerNotifier.projectorBeside(model.path)?.path,
      projector.path,
    );
  });

  test('a text-only model gets no projector', () {
    final model = touch('Llama-3.2-3B-Instruct-Q4_K_M.gguf');
    touch('Qwen3-8B-Q4_K_M.gguf');
    expect(ModelManagerNotifier.projectorBeside(model.path), isNull);
  });
}
