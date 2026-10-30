import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../desktop/engine_files.dart';

/// Only binds our stable ABI. Upstream structs stay in C++.
class LlamaBindings {
  static const supportedAbi = 7;

  /// The fast CPU bridge is independent of the optional OpenCL driver.
  /// OpenCL builds retain GPU support; CPU-only builds still get the same
  /// Armv8.6+dotprod+i8mm+fp16 kernels. Older CPUs use portable Armv8-A.
  /// The selected library and skipped candidates are recorded in metrics.
  static const androidVariants = [
    'libondevice_llm_opencl.so',
    'libondevice_llm_cpu_i8mm.so',
    'libondevice_llm.so',
  ];

  static bool variantNeedsI8mm(String name) =>
      name == 'libondevice_llm_opencl.so' ||
      name == 'libondevice_llm_cpu_i8mm.so';

  /// Which library was opened, and why any preferred variant was skipped.
  late final String library;
  final List<String> skipped = [];

  /// [windowsBackend] ('cuda' or 'vulkan') tries that bridge first: each
  /// Windows bridge carries only its own GPU backend.
  /// [libraryPath] reopens a worker's already selected library without probing.
  LlamaBindings({
    String? windowsBackend,
    String cpuVariant = 'auto',
    String? libraryPath,
  }) {
    final lib = libraryPath != null
        ? (libraryPath == 'process' ? _process() : _open(libraryPath))
        : Platform.isAndroid
        ? _openAndroid()
        : Platform.isWindows
        ? _openWindows(windowsBackend, cpuVariant)
        : _process();
    final version = lib.lookupFunction<Int32 Function(), int Function()>(
      'od_version',
    );
    if (version() != supportedAbi) {
      throw StateError(
        'Unsupported native bridge ABI ${version()}; expected $supportedAbi',
      );
    }
    create = lib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>),
          Pointer<Void> Function(Pointer<Utf8>)
        >('od_create');
    destroy = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('od_destroy');
    error = lib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>),
          Pointer<Utf8> Function(Pointer<Void>)
        >('od_error');
    info = lib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>),
          Pointer<Utf8> Function(Pointer<Void>)
        >('od_info');
    load = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
        >('od_load');
    begin = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Utf8>),
          int Function(Pointer<Void>, Pointer<Utf8>)
        >('od_begin');
    preview = lib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)
        >('od_preview');
    step = lib
        .lookupFunction<
          Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Int32>),
          int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Int32>)
        >('od_step');
    embed = lib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)
        >('od_embed');
    adapterInfo = lib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>),
          Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>)
        >('od_adapter_info');
    if (lib.providesSymbol('od_estimate')) {
      estimate = lib
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>),
            Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)
          >('od_estimate');
    }
    if (lib.providesSymbol('od_load_progress')) {
      loadProgress = lib
          .lookupFunction<Float Function(Int64), double Function(int)>(
            'od_load_progress',
          );
    }
    if (lib.providesSymbol('od_cancel_session')) {
      sessionId = lib
          .lookupFunction<
            Int64 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('od_session_id');
      cancelSession = lib
          .lookupFunction<Void Function(Int64), void Function(int)>(
            'od_cancel_session',
          );
      resetCancel = lib
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('od_reset_cancel');
      cancelled = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>),
            int Function(Pointer<Void>)
          >('od_cancelled');
    }
  }
  DynamicLibrary _open(String name) {
    // Assign only after success: `library` is final and a failed variant
    // must not claim it.
    final lib = DynamicLibrary.open(name);
    library = name;
    return lib;
  }

  /// CUDA, then hardware Vulkan, then CPU. Overrides try only that GPU.
  DynamicLibrary _openWindows(String? preferred, String cpuVariant) {
    final selected = openWindowsLibrary<DynamicLibrary>(
      skipped: skipped,
      preferred: preferred,
      cpuVariant: cpuVariant,
      open: DynamicLibrary.open,
      checkEngineFiles: EngineFiles.besideExecutable().checkVariant,
      gpuDeviceCount: (lib) =>
          lib.lookupFunction<Int32 Function(), int Function()>(
            'od_gpu_device_count',
          )(),
    );
    library = selected.name;
    return selected.handle;
  }

  /// The GPU backend of an opened Windows bridge name ('vulkan' for
  /// ondevice_llm_vulkan.dll), so another isolate can open the same DLL;
  /// null for the CPU bridge and other platforms.
  static String? windowsGpuOf(String? library) => switch (library) {
    final l? when l.contains('_vulkan') => 'vulkan',
    final l? when l.contains('_cuda') => 'cuda',
    _ => null,
  };

  /// Windows checks both CPU support and OS AVX state management.
  static bool windowsHasAvx2() {
    final present = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Int32 Function(Uint32), int Function(int)>(
          'IsProcessorFeaturePresent',
        );
    return present(40) != 0; // PF_AVX2_INSTRUCTIONS_AVAILABLE
  }

  static bool windowsHasAvx512() {
    final present = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Int32 Function(Uint32), int Function(int)>(
          'IsProcessorFeaturePresent',
        );
    return present(41) != 0; // PF_AVX512F_INSTRUCTIONS_AVAILABLE
  }

  static String? windowsCpuOf(String? library) => switch (library) {
    'ondevice_llm_avx512.dll' => 'avx512',
    'ondevice_llm.dll' => 'avx2',
    'ondevice_llm_compat.dll' => 'compat',
    _ => null,
  };

  // Set from the paired local hardware smoke measurements.
  static const autoAvx512 = false;

  /// Injectable OS and loader checks keep tests independent of host hardware.
  static ({String name, T handle}) openWindowsLibrary<T>({
    required List<String> skipped,
    required T Function(String) open,
    required int Function(T) gpuDeviceCount,
    Map<String, String>? environment,
    bool Function(String)? fileExists,
    List<EngineFileResult> Function(String)? checkEngineFiles,
    bool Function()? hasAvx2,
    bool Function()? hasAvx512,
    String cpuVariant = 'auto',
    String? preferred,
  }) {
    final env = environment ?? Platform.environment;
    final exists = fileExists ?? (path) => File(path).existsSync();
    final root = env['SystemRoot'] ?? r'C:\Windows';
    final override = env['ODLLM_WINDOWS_BACKEND']?.trim().toLowerCase();
    final forced = const [
      'cpu',
      'compat',
      'cuda',
      'cuda12',
      'vulkan',
    ].contains(override);
    final avx2 = (hasAvx2 ?? windowsHasAvx2)();
    if (override != null && override.isNotEmpty && !forced) {
      skipped.add(
        'ODLLM_WINDOWS_BACKEND: unknown backend "$override"; using auto',
      );
    }
    // The CUDA 12 bridge serves drivers too old for CUDA 13 and the
    // Pascal/Volta GPUs CUDA 13 dropped.
    final order = preferred == 'vulkan'
        ? const ['vulkan', 'cuda', 'cuda12']
        : const ['cuda', 'cuda12', 'vulkan'];
    for (final backend in order) {
      final name = 'ondevice_llm_$backend.dll';
      if (!avx2) {
        skipped.add('$name: this CPU lacks AVX2');
        continue;
      }
      if ((preferred == 'cpu' && !forced) ||
          (forced &&
              override != backend &&
              !(override == 'cuda' && backend == 'cuda12'))) {
        skipped.add(
          forced
              ? '$name: overridden by ODLLM_WINDOWS_BACKEND=$override'
              : '$name: CPU backend selected',
        );
        continue;
      }
      final nvidia = backend.startsWith('cuda');
      final driver = nvidia ? 'nvcuda.dll' : 'vulkan-1.dll';
      if (!exists('$root\\System32\\$driver')) {
        skipped.add('$name: no ${nvidia ? 'NVIDIA' : 'Vulkan'} driver');
        continue;
      }
      final damaged =
          checkEngineFiles?.call(name) ?? const <EngineFileResult>[];
      if (damaged.isNotEmpty) {
        skipped.add(
          '$name: ${damaged.map((r) => '${r.name} (${r.status.name})').join(', ')}',
        );
        continue;
      }
      try {
        final lib = open(name);
        if (gpuDeviceCount(lib) <= 0) {
          skipped.add(
            nvidia
                ? '$name: no GPU this CUDA runtime can use (driver too old?)'
                : '$name: no hardware GPU devices',
          );
          continue;
        }
        return (name: name, handle: lib);
      } catch (e) {
        skipped.add('$name: $e');
      }
    }
    final requested = override == 'compat' ? 'compat' : cpuVariant;
    final avx512 = (hasAvx512 ?? windowsHasAvx512)();
    final variants = <String>[
      if (requested == 'avx512' || (requested == 'auto' && autoAvx512))
        'avx512',
      if (requested != 'compat') 'avx2',
      'compat',
    ];
    Object? failure;
    for (final variant in variants) {
      final name = variant == 'avx2'
          ? 'ondevice_llm.dll'
          : 'ondevice_llm_$variant.dll';
      if ((variant == 'avx512' && (!avx512 || !avx2)) ||
          (variant == 'avx2' && !avx2)) {
        skipped.add('$name: OS reports $variant unavailable');
        continue;
      }
      final damaged =
          checkEngineFiles?.call(name) ?? const <EngineFileResult>[];
      if (damaged.isNotEmpty) {
        skipped.add(
          '$name: ${damaged.map((r) => '${r.name} (${r.status.name})').join(', ')}',
        );
        continue;
      }
      try {
        return (name: name, handle: open(name));
      } catch (e) {
        failure = e;
        skipped.add('$name: $e; trying the next CPU variant');
      }
    }
    throw StateError('No usable CPU bridge: $failure; ${skipped.join('; ')}');
  }

  DynamicLibrary _process() {
    library = 'process';
    return DynamicLibrary.process();
  }

  /// The fast variant is compiled for armv8.6+i8mm; a CPU without i8mm
  /// would hit SIGILL, which no catch can recover, so check first.
  /// [cpuinfo] replaces /proc/cpuinfo in tests.
  static bool cpuHasI8mm({String? cpuinfo}) {
    try {
      final info = cpuinfo ?? File('/proc/cpuinfo').readAsStringSync();
      // Every core lists its own Features line; the fast library runs on
      // whichever core the scheduler picks, so all of them must have i8mm.
      final lines = RegExp(
        r'^Features\s*:\s*(.*)$',
        multiLine: true,
      ).allMatches(info).toList();
      if (lines.isEmpty) return false;
      return lines.every(
        (m) => m.group(1)!.trim().split(RegExp(r'\s+')).contains('i8mm'),
      );
    } catch (_) {
      return false;
    }
  }

  DynamicLibrary _openAndroid() {
    Object? last;
    for (final name in androidVariants) {
      if (variantNeedsI8mm(name) && !cpuHasI8mm()) {
        skipped.add('$name: this CPU lacks i8mm');
        continue;
      }
      try {
        return _open(name);
      } catch (e) {
        last = e;
        skipped.add('$name: $e');
      }
    }
    throw StateError('No native bridge library could be loaded: $last');
  }

  late final Pointer<Void> Function(Pointer<Utf8>) create;
  late final void Function(Pointer<Void>) destroy;
  late final Pointer<Utf8> Function(Pointer<Void>) error, info;
  late final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) load;
  late final int Function(Pointer<Void>, Pointer<Utf8>) begin;
  late final Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>) preview,
      embed,
      adapterInfo;
  late final int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Int32>)
  step;
  int Function(Pointer<Void>)? sessionId, cancelled;

  /// What a load would use, without loading (optional export; older
  /// bridges lack it).
  Pointer<Utf8> Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)? estimate;
  void Function(int)? cancelSession;
  double Function(int)? loadProgress;
  void Function(Pointer<Void>)? resetCancel;
}
