import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/inference/ffi/llama_bindings.dart';
import 'package:path/path.dart' as p;

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
    open: (path) {
      final name = path.split(RegExp(r'[\\/]')).last;
      opened.add(name);
      if (failures.contains(name)) throw StateError('missing DLL/dependency');
      return name;
    },
    gpuDeviceCount: (_) {
      if (queryFails) throw StateError('missing query');
      return devices;
    },
  ).name.split(RegExp(r'[\\/]')).last;

  test('Windows bridge load requires a restricted absolute preload', () {
    const bridge = r'C:\verified\ondevice_llm.dll';
    final module = Pointer<Void>.fromAddress(1);
    final calls = <String>[];
    String load(String path, {bool missingDependency = false}) =>
        WindowsBridgeLoader.openRestricted(
          path,
          preload: (name, flags) {
            calls.add('preload');
            expect(name.toDartString(), bridge);
            expect(flags, 0x100 | 0x200 | 0x800);
            return missingDependency ? nullptr : module;
          },
          bind: (path) {
            calls.add('bind');
            return path;
          },
          release: (handle) {
            calls.add('release');
            expect(handle, module);
            return 1;
          },
        );

    expect(() => load(cpu), throwsArgumentError);
    expect(calls, isEmpty);
    expect(() => load(bridge, missingDependency: true), throwsStateError);
    expect(calls, ['preload']);
    calls.clear();
    expect(load(bridge), bridge);
    expect(calls, ['preload', 'bind', 'release']);
  });

  test('reopen refuses an absolute path that is not already mapped', () {
    if (!Platform.isWindows) return;
    final temp = Directory.systemTemp.createTempSync('od-reopen');
    addTearDown(() => temp.deleteSync(recursive: true));
    expect(
      () => WindowsBridgeLoader.reopen(p.join(temp.path, 'not-mapped.dll')),
      throwsArgumentError,
    );
  });

  test('reopen reuses an already mapped bridge outside the app dir', () {
    if (!Platform.isWindows) return;
    final system = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final kernel = p.join(system, 'System32', 'kernel32.dll');
    WindowsBridgeLoader.open(kernel);
    expect(WindowsBridgeLoader.reopen(kernel), isA<DynamicLibrary>());
  });

  test(
    'a verified bridge is write-locked and re-hashed before it is mapped',
    () {
      if (!Platform.isWindows) return;
      final temp = Directory.systemTemp.createTempSync('od-verify');
      addTearDown(() => temp.deleteSync(recursive: true));
      final bridge = File(p.join(temp.path, 'ondevice_llm.dll'))
        ..writeAsBytesSync([1, 2, 3, 4]);
      final digest = sha256.convert(bridge.readAsBytesSync()).toString();
      final module = Pointer<Void>.fromAddress(1);
      final calls = <String>[];

      final loaded = WindowsBridgeLoader.openRestricted<String>(
        bridge.path,
        expectedSha256: digest,
        // While the handle is held, the hash is already checked and the module
        // is not mapped yet: no writer or deleter may get in.
        preload: (name, flags) {
          calls.add('preload');
          expect(flags, 0x200 | 0x800);
          expect(
            () => bridge.writeAsBytesSync([9]),
            throwsA(isA<FileSystemException>()),
          );
          expect(
            () => bridge.deleteSync(),
            throwsA(isA<FileSystemException>()),
          );
          return module;
        },
        bind: (path) {
          calls.add('bind');
          return path;
        },
        release: (handle) {
          calls.add('release');
          expect(handle, module);
          return 1;
        },
      );
      expect(loaded, bridge.path);
      expect(calls, ['preload', 'bind', 'release']);
      // The lock is gone once the load returned.
      bridge.writeAsBytesSync([5]);

      calls.clear();
      expect(
        () => WindowsBridgeLoader.openRestricted<String>(
          bridge.path,
          expectedSha256: 'a' * 64,
          preload: (_, _) {
            calls.add('preload');
            return module;
          },
          bind: (path) => path,
          release: (_) => 1,
        ),
        throwsStateError,
      );
      expect(calls, isEmpty);
    },
  );

  test(
    'standalone ISA probes use the bundled bridge with both packs installed',
    () {
      final saved = LlamaBindings.enginePack;
      final savedIk = LlamaBindings.ikEnginePack;
      final defaultPack = _RecordingPack();
      final ik = _RecordingPack();
      LlamaBindings.enginePack = defaultPack;
      LlamaBindings.ikEnginePack = ik;
      addTearDown(() {
        LlamaBindings.enginePack = saved;
        LlamaBindings.ikEnginePack = savedIk;
      });
      final opened = <String>[];
      expect(
        LlamaBindings.windowsProbeIsa(
          readIsa: (path) {
            opened.add(path);
            return 3;
          },
        ),
        3,
      );
      expect(defaultPack.lookups, 0);
      expect(ik.lookups, 0);
      expect(opened, [LlamaBindings.windowsBridgePath(compat)]);
    },
  );

  test(
    'bundled fallback uses its absolute path with a same-name pack mapped',
    () {
      const app = r'C:\Program Files\OnDevice';
      const pack = r'C:\engines\new';
      final mapped = <String, String>{cpu: 'pack module'};
      final opened = <String>[];
      String load(String path) {
        opened.add(path);
        return mapped.putIfAbsent(path, () => 'bundled module');
      }

      final selected = LlamaBindings.openWindowsLibrary<String>(
        skipped: [],
        preferred: 'cpu',
        cpuVariant: 'avx2',
        executableDirectory: app,
        hasAvx2: () => true,
        hasAvx512: () => false,
        environment: const {},
        fileExists: (_) => false,
        open: load,
        gpuDeviceCount: (_) => 0,
      );
      expect(selected.name, '$app\\$cpu');
      expect(selected.handle, 'bundled module');
      expect(opened, ['$app\\$cpu']);
      for (final bridge in [
        compat,
        cuda,
        cuda12,
        vulkan,
        'ondevice_llm_avx512.dll',
        'ondevice_sd.dll',
        'ondevice_sd_cpu.dll',
        'ondevice_sd_compat.dll',
      ]) {
        expect(
          LlamaBindings.windowsBridgePath(bridge, executableDirectory: app),
          '$app\\$bridge',
        );
      }
      // Explicit reopen in the engine isolate and the ISA probe share this helper.
      expect(
        LlamaBindings.windowsBridgePath(cpu, executableDirectory: app),
        selected.name,
      );
      expect(
        LlamaBindings.windowsBridgePath(
          selected.name,
          executableDirectory: app,
        ),
        selected.name,
      );
      expect(
        LlamaBindings.windowsBridgePath(
          '$pack\\$cpu',
          executableDirectory: app,
        ),
        '$pack\\$cpu',
      );
    },
  );

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

class _RecordingPack implements EnginePackLoader {
  int lookups = 0;

  @override
  String? get rootPath => r'C:\engines\ik_llama';

  @override
  String? activePackDir() {
    lookups++;
    return r'C:\engines\ik_llama\ik-1234567';
  }

  @override
  String? verifiedPackDir() => activePackDir();

  @override
  String? expectedFileSha256(String dir, String name) => null;

  @override
  int? get cudaMajor => null;

  @override
  List<String> get unavailableFiles => const [];

  @override
  bool markLoadStarted() => true;

  @override
  void markLoadSucceeded() {}
}
