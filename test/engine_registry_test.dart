import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/settings/domain/setting_specs.dart';
import 'package:ondevice_llm/inference/engine/engine_descriptor.dart';
import 'package:ondevice_llm/inference/engine/engine_registry.dart';

ModelInfo model(String name, {String? localPath}) => ModelInfo(
  id: 'model',
  displayName: 'Model',
  fileName: name,
  sizeBytes: 0,
  family: ModelFamily.other,
  quantization: ModelQuantization.unknown,
  localPath: localPath,
);

void main() {
  final pack = EngineDescriptor(
    id: 'test-pack',
    displayName: 'Test engine pack',
    platforms: {'android'},
    extensions: {'.gguf'},
    distribution: EngineDistribution.signedPack,
    capabilities: llamaCppEngine.capabilities,
  );

  test('resolves the actual model file and ignores extension case', () {
    final registry = EngineRegistry(platform: 'android');

    expect(registry.available, [llamaCppEngine, liteRtLmEngine]);
    expect(registry.resolve(model('model.GGUF')), llamaCppEngine);
    expect(
      registry.resolve(model('old.gguf', localPath: 'new.LiteRTLM')),
      liteRtLmEngine,
    );
    expect(registry.resolve(model('model.onnx')), isNull);
  });

  test('uses a compatible installed override with format defaults', () {
    final registry = EngineRegistry(
      platform: 'android',
      engines: [...bundledTextEngines, pack],
      installedPacks: {pack.id},
      overrides: {model('').id: pack.id},
    );

    expect(registry.resolve(model('model.gguf')), pack);
    expect(registry.resolve(model('model.litertlm')), liteRtLmEngine);
    expect(
      registry.resolve(model('model.gguf'), overrideId: llamaCppEngine.id),
      llamaCppEngine,
    );
  });

  test(
    'ignores missing packs and rejects models without an available engine',
    () {
      final android = EngineRegistry(
        platform: 'android',
        engines: [...bundledTextEngines, pack],
      );
      final windows = EngineRegistry(platform: 'windows');

      expect(android.available, isNot(contains(pack)));
      expect(
        android.resolve(model('model.gguf'), overrideId: pack.id),
        llamaCppEngine,
      );
      expect(windows.available, [llamaCppEngine]);
      expect(windows.resolve(model('model.litertlm')), isNull);
      expect(windows.descriptorFor(model('model.litertlm')), liteRtLmEngine);
    },
  );

  test('capabilities gate controls, hosting, and helper use', () {
    final registry = EngineRegistry(platform: 'android');
    final liteRt = registry.resolve(model('model.litertlm'))!.capabilities;
    final llama = registry.resolve(model('model.gguf'))!.capabilities;

    expect(liteRt.streaming && liteRt.cancel && liteRt.vision, isTrue);
    expect(liteRt.tools || liteRt.hosting || liteRt.optimize, isFalse);
    expect(liteRt.helpers, EngineHelperMode.sharedChat);
    expect(liteRt.loadKeys, {'liteRtBackend', 'visionEnabled'});
    expect(liteRt.samplingKeys, {'temperature', 'topK', 'topP', 'maxTokens'});
    expect(SettingSpec.byKey('temperature')!.usedBy(liteRt), isTrue);
    expect(SettingSpec.byKey('minP')!.usedBy(liteRt), isFalse);
    expect(SettingSpec.byKey('contextSize')!.usedBy(liteRt), isFalse);
    expect(SettingSpec.byKey('liteRtBackend')!.usedBy(llama), isFalse);
    expect(llama.hosting && llama.optimize, isTrue);
    expect(llama.helpers, EngineHelperMode.dedicated);
  });
}
