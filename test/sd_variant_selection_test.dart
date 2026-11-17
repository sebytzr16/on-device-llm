import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/ffi/sd_bindings.dart';

// GitHub issue #4: the image engine must never be one build tuned for the
// build machine's CPU. The loader picks the CUDA, AVX2 or SSE4.2 variant.
void main() {
  const cuda = 'ondevice_sd.dll';
  const cpu = SdBindings.cpuDllName;
  const compat = SdBindings.compatDllName;
  const nvcuda = r'C:\Windows\System32\nvcuda.dll';

  List<String> pick({
    String variant = 'auto',
    bool avx2 = true,
    Set<String> files = const {cuda, cpu, compat, nvcuda},
    Map<String, String> env = const {'SystemRoot': r'C:\Windows'},
  }) => SdBindings.candidates(
    cpuVariant: variant,
    hasAvx2: () => avx2,
    exists: files.contains,
    environment: env,
  );

  test(
    'NVIDIA PC with AVX2 tries CUDA, then the AVX2 and SSE4.2 CPU builds',
    () {
      expect(pick(), [cuda, cpu, compat]);
    },
  );

  test('no NVIDIA driver skips the CUDA build', () {
    expect(pick(files: {cuda, cpu, compat}), [cpu, compat]);
  });

  test('a CPU without AVX2 only gets the SSE4.2 build', () {
    expect(pick(avx2: false), [compat]);
  });

  test('the SSE4.2 compatibility setting applies to images too', () {
    expect(pick(variant: 'compat'), [compat]);
  });

  test('ODLLM_WINDOWS_BACKEND=cpu keeps images off the GPU', () {
    expect(
      pick(env: {'SystemRoot': r'C:\Windows', 'ODLLM_WINDOWS_BACKEND': 'cpu'}),
      [cpu, compat],
    );
  });

  test('a CPU-only install without the CUDA build still makes images', () {
    expect(pick(files: {cpu, compat, nvcuda}), [cpu, compat]);
  });

  test('nothing installed means no candidates', () {
    expect(pick(files: const {}), isEmpty);
  });
}
