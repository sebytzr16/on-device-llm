import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';

void main() {
  const cpu = 'ondevice_llm.dll';
  const compat = 'ondevice_llm_compat.dll';
  const cuda = 'ondevice_llm_cuda.dll';
  const cuda12 = 'ondevice_llm_cuda12.dll';
  const vulkan = 'ondevice_llm_vulkan.dll';
  late List<String> skipped;
  late List<String> opened;
  late List<String> checked;

  String select({
    String? backend,
    Set<String> drivers = const {'nvcuda.dll', 'vulkan-1.dll'},
    Set<String> failures = const {},
    int devices = 1,
    bool queryFails = false,
    String? preferred,
    bool avx2 = true,
    bool avx512 = false,
    String cpuVariant = 'auto',
    bool compatExists = true,
  }) => LlamaBindings.openWindowsLibrary<String>(
    skipped: skipped,
    preferred: preferred,
    hasAvx2: () => avx2,
    hasAvx512: () => avx512,
    cpuVariant: cpuVariant,
    environment: {
      'SystemRoot': r'Z:\Windows',
      'ODLLM_WINDOWS_BACKEND': ?backend,
    },
    fileExists: (path) {
      checked.add(path);
      if (path.endsWith('\\$compat')) return compatExists;
      return drivers.any((driver) => path == 'Z:\\Windows\\System32\\$driver');
    },
    open: (name) {
      opened.add(name);
      if (failures.contains(name)) throw StateError('missing DLL/dependency');
      return name;
    },
    gpuDeviceCount: (_) {
      if (queryFails) throw StateError('missing query');
      return devices;
    },
  ).name;

  setUp(() {
    skipped = [];
    opened = [];
    checked = [];
  });

  test('CUDA wins when its driver and DLL are available', () {
    expect(select(), cuda);
    expect(opened, [cuda]);
    expect(checked, [r'Z:\Windows\System32\nvcuda.dll']);
    expect(skipped, isEmpty);
  });
  test('choosing Vulkan in Settings opens Vulkan before CUDA', () {
    expect(select(preferred: 'vulkan'), vulkan);
    expect(opened, [vulkan]);
  });
  test('a Vulkan choice without Vulkan still finds CUDA', () {
    expect(select(preferred: 'vulkan', drivers: {'nvcuda.dll'}), cuda);
    expect(skipped.single, contains('no Vulkan driver'));
  });
  test('the environment override beats the Settings choice', () {
    expect(select(backend: 'cuda', preferred: 'vulkan'), cuda);
  });
  test('cancel reopens the bridge the worker opened', () {
    expect(LlamaBindings.windowsGpuOf(vulkan), 'vulkan');
    expect(LlamaBindings.windowsGpuOf(cuda), 'cuda');
    expect(LlamaBindings.windowsGpuOf(cpu), isNull);
    expect(LlamaBindings.windowsGpuOf(compat), isNull);
    expect(LlamaBindings.windowsGpuOf(null), isNull);
    expect(select(preferred: LlamaBindings.windowsGpuOf(vulkan)), vulkan);
  });
  test('missing NVIDIA driver selects Vulkan', () {
    expect(select(drivers: {'vulkan-1.dll'}), vulkan);
    expect(opened, [vulkan]);
    expect(skipped, hasLength(2));
    expect(skipped.every((s) => s.contains('no NVIDIA driver')), isTrue);
  });
  test('CUDA 13 load failure falls back to the CUDA 12 bridge', () {
    expect(select(failures: {cuda}), cuda12);
    expect(opened, [cuda, cuda12]);
    expect(skipped.single, contains('missing DLL/dependency'));
  });
  test('a CUDA runtime that sees no GPU (old driver) falls through', () {
    expect(select(devices: 0, drivers: {'nvcuda.dll'}), cpu);
    expect(opened, [cuda, cuda12, cpu]);
    expect(skipped.first, contains('driver too old'));
  });
  test('both CUDA bridges failing selects Vulkan', () {
    expect(select(failures: {cuda, cuda12}), vulkan);
    expect(opened, [cuda, cuda12, vulkan]);
    expect(skipped, hasLength(2));
  });
  test('CUDA 12 can be forced and is the forced-CUDA fallback', () {
    expect(select(backend: 'cuda12'), cuda12);
    expect(opened, [cuda12]);
    expect(LlamaBindings.windowsGpuOf(cuda12), 'cuda');
    opened.clear();
    expect(select(backend: 'cuda', failures: {cuda}), cuda12);
    expect(opened, [cuda, cuda12]);
  });
  test('missing drivers selects CPU without opening GPU DLLs', () {
    expect(select(drivers: {}), cpu);
    expect(opened, [cpu]);
    expect(skipped, hasLength(3));
    expect(skipped.last, contains('no Vulkan driver'));
  });
  test('Vulkan load failure falls back to CPU', () {
    expect(select(drivers: {'vulkan-1.dll'}, failures: {vulkan}), cpu);
    expect(opened, [vulkan, cpu]);
    expect(skipped.last, contains('missing DLL/dependency'));
  });
  test('software-only or absent Vulkan GPU falls back to CPU', () {
    expect(select(backend: 'vulkan', devices: 0), cpu);
    expect(opened, [vulkan, cpu]);
    expect(skipped.last, contains('no hardware GPU devices'));
  });
  test('missing Vulkan device query falls back to CPU', () {
    expect(select(backend: 'vulkan', queryFails: true), cpu);
    expect(skipped.last, contains('missing query'));
  });
  test('CPU override never probes drivers or opens GPU DLLs', () {
    expect(select(backend: 'cpu'), cpu);
    expect(opened, [cpu]);
    expect(checked, isEmpty);
    expect(skipped.every((s) => s.contains('overridden')), isTrue);
  });
  test('Vulkan override skips working CUDA', () {
    expect(select(backend: 'vulkan'), vulkan);
    expect(opened, [vulkan]);
    expect(checked, [r'Z:\Windows\System32\vulkan-1.dll']);
  });
  test('failed forced CUDA goes directly to CPU', () {
    expect(select(backend: 'cuda', failures: {cuda, cuda12}), cpu);
    expect(opened, [cuda, cuda12, cpu]);
  });
  test('forced CUDA with no driver goes directly to CPU', () {
    expect(select(backend: 'cuda', drivers: {'vulkan-1.dll'}), cpu);
    expect(opened, [cpu]);
  });
  test('forced Vulkan without its driver goes directly to CPU', () {
    expect(select(backend: 'vulkan', drivers: {'nvcuda.dll'}), cpu);
    expect(opened, [cpu]);
  });
  test('override ignores surrounding whitespace and case', () {
    expect(select(backend: ' VULKAN '), vulkan);
  });
  test('unknown override records a diagnostic and uses automatic order', () {
    expect(select(backend: 'other'), cuda);
    expect(skipped.single, contains('unknown backend'));
  });
  test('CPU load failure propagates', () {
    expect(select(backend: 'cpu', failures: {cpu}), compat);
  });
  test('no AVX2 skips the GPU bridges and the fast CPU bridge', () {
    expect(select(avx2: false), compat);
    expect(opened, [compat]);
    expect(skipped.where((s) => s.contains('lacks AVX2')), hasLength(3));
    expect(checked.any((s) => s.contains('System32')), isFalse);
  });
  for (final backend in ['cpu', 'cuda', 'cuda12', 'vulkan', 'compat']) {
    test('$backend override respects a CPU without AVX2', () {
      expect(select(backend: backend, avx2: false), compat);
      expect(opened, [compat]);
    });
  }
  test('compat override selects the portable bridge on an AVX2 CPU', () {
    expect(select(backend: ' COMPAT '), compat);
    expect(opened, [compat]);
  });
  test('compat load failure propagates without trying an AVX2 bridge', () {
    expect(() => select(avx2: false, failures: {compat}), throwsStateError);
    expect(opened, [compat]);
  });
}
