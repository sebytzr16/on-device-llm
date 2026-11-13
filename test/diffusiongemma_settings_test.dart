import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';
import 'package:ondevice_llm/inference/engine/diffusiongemma_engine.dart';

/// The value that follows [flag] on a command line, or null when absent.
String? _arg(List<String> args, String flag) {
  final at = args.indexOf(flag);
  return at < 0 || at + 1 >= args.length ? null : args[at + 1];
}

void main() {
  final engine = DiffusionGemmaEngine(executable: 'dg_host.exe');

  test('dg_host launch args carry the resolved load settings', () {
    const settings = InferenceSettings(
      contextSize: 8192,
      nGpuLayers: 24,
      cpuThreads: 6,
      batchThreads: 5,
      microBatchSize: 256,
      seed: 1234,
    );
    final args = engine.launchArgs(r'C:\models\dg.gguf', settings);
    expect(_arg(args, '-m'), r'C:\models\dg.gguf');
    expect(_arg(args, '-c'), '8192');
    expect(_arg(args, '-ngl'), '24');
    expect(_arg(args, '-t'), '6');
    expect(_arg(args, '-tb'), '5');
    expect(_arg(args, '-ub'), '256');
    expect(_arg(args, '-b'), '256');
    expect(_arg(args, '-s'), '1234');
    // The model's own placement and diffusion flags stay fixed.
    expect(_arg(args, '-ot'), 'exps=CPU');
    expect(_arg(args, '--diffusion-eb'), 'on');
  });

  test('auto threads stay positive and a random seed is not forced', () {
    const settings = InferenceSettings(cpuThreads: 0, batchThreads: 0, seed: 0);
    final args = engine.launchArgs('dg.gguf', settings);
    expect(_arg(args, '-t'), '${settings.effectiveThreads}');
    expect(int.parse(_arg(args, '-t')!), greaterThan(0));
    expect(_arg(args, '-tb'), '${settings.effectiveBatchThreads}');
    expect(args, isNot(contains('-s')));
  });

  test('micro-batch falls back to the engine default', () {
    final defaulted = DiffusionGemmaEngine(
      executable: 'dg_host.exe',
      ubatch: 128,
    );
    final args = defaulted.launchArgs('dg.gguf', const InferenceSettings());
    expect(_arg(args, '-ub'), '128');
    expect(_arg(args, '-b'), '128');
  });

  test('only the load controls dg_host honours are advertised', () {
    for (final key in const [
      'contextSize',
      'nGpuLayers',
      'cpuThreads',
      'batchThreads',
      'microBatchSize',
      'seed',
    ]) {
      expect(diffusionGemmaHonoursLoad(key), isTrue, reason: key);
    }
    for (final key in const [
      'flashAttention',
      'kvCacheType',
      'speculationMode',
      'mainGpu',
      'useMmap',
      'nCpuMoe',
      'chatTemplate',
    ]) {
      expect(diffusionGemmaHonoursLoad(key), isFalse, reason: key);
    }
  });
}
