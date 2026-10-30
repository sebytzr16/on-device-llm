import 'package:ondevice_llm/core/l10n/cpu_variant_labels.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:ondevice_llm/features/settings/domain/entities/inference_settings.dart';

void main() {
  const avx512Dll = 'ondevice_llm_avx512.dll';
  const avx2Dll = 'ondevice_llm.dll';
  const compatDll = 'ondevice_llm_compat.dll';
  late List<String> opened;
  late List<String> skipped;
  String select({
    String variant = 'auto',
    bool avx512 = true,
    bool avx2 = true,
    Set<String> failures = const {},
  }) => LlamaBindings.openWindowsLibrary<String>(
    skipped: skipped,
    preferred: 'cpu',
    cpuVariant: variant,
    environment: const {},
    hasAvx2: () => avx2,
    hasAvx512: () => avx512,
    fileExists: (_) => false,
    gpuDeviceCount: (_) => 0,
    open: (name) {
      opened.add(name);
      if (failures.contains(name)) throw StateError('missing dependency');
      return name;
    },
  ).name;
  setUp(() {
    opened = [];
    skipped = [];
  });
  test('auto follows the measured policy on AVX512 hardware', () {
    expect(select(), LlamaBindings.autoAvx512 ? avx512Dll : avx2Dll);
  });
  test('forced AVX512 requires OS support', () {
    expect(select(variant: 'avx512', avx512: false), avx2Dll);
    expect(opened, [avx2Dll]);
    expect(skipped.join(), contains('OS reports avx512 unavailable'));
  });
  test('forced AVX512 loads only the CPU bridge', () {
    expect(select(variant: 'avx512'), avx512Dll);
    expect(opened, [avx512Dll]);
  });
  test('missing forced AVX512 falls back with a reason', () {
    expect(select(variant: 'avx512', failures: {avx512Dll}), avx2Dll);
    expect(opened, [avx512Dll, avx2Dll]);
    expect(skipped.join(), contains('missing dependency'));
  });
  test('missing AVX2 falls back to compat', () {
    expect(select(variant: 'avx2', failures: {avx2Dll}), compatDll);
  });
  test('no AVX2 never opens an AVX bridge', () {
    expect(select(variant: 'avx512', avx2: false), compatDll);
    expect(opened, [compatDll]);
  });
  test('compat never opens a faster bridge', () {
    expect(select(variant: 'compat'), compatDll);
    expect(opened, [compatDll]);
  });
  test('no usable bridge fails instead of loading unsafe instructions', () {
    expect(() => select(avx2: false, failures: {compatDll}), throwsStateError);
    expect(opened, [compatDll]);
  });
  test(
    'fallback UI explains OS and DLL failures with the selected variant',
    () {
      final t = AppLocalizationsEn();
      final metrics = <String, dynamic>{
        'nativeLibrary': avx2Dll,
        'nativeLibrarySkipped': [
          'ondevice_llm_avx512.dll: OS reports avx512 unavailable',
        ],
      };
      expect(cpuVariantFallback(t, metrics), t.avx512OsFallback('AVX2'));
      metrics['nativeLibrarySkipped'] = [
        'missing dependency; trying the next CPU variant',
      ];
      expect(cpuVariantFallback(t, metrics), t.avx512LoadFallback('AVX2'));
      metrics['nativeLibrarySkipped'] = [];
      expect(cpuVariantFallback(t, metrics), isNull);
    },
  );
  test('variant persists and reaches the worker load configuration', () {
    final settings = const InferenceSettings().copyWith(cpuVariant: 'avx512');
    final restored = InferenceSettings.fromJson(settings.toJson());
    expect(restored.cpuVariant, 'avx512');
    expect(
      jsonDecode(LlamaEngine.loadConfig(settings: restored))['cpuVariant'],
      'avx512',
    );
    expect(
      InferenceSettings.fromJson({'cpuVariant': 'unknown'}).cpuVariant,
      'auto',
    );
    expect(LlamaBindings.windowsCpuOf(avx512Dll), 'avx512');
  });
}
