import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import '../../desktop/engine_files.dart';

/// Version of the Dart-to-bridge surface: every export and signature the app
/// binds. An engine pack declares the same number, so a mismatched pack is
/// never installed. Bump this when any FFI signature or export used by the
/// app changes.
const kEngineBridgeApi = 1;

/// Every export the chat bridge bindings look up, optional ones included. The
/// engine pack smoke test opens a downloaded DLL in a child process and
/// requires all of them, so a half-built pack cannot replace a working engine.
/// windows/runner/CMakeLists.txt generates the native probe list from this list.
const List<String> kBridgeExports = [
  'od_version',
  'od_create',
  'od_destroy',
  'od_error',
  'od_info',
  'od_load',
  'od_begin',
  'od_preview',
  'od_step',
  'od_embed',
  'od_adapter_info',
  'od_side_open',
  'od_side_submit',
  'od_side_step',
  'od_side_cancel',
  'od_side_close',
  'od_estimate',
  'od_load_progress',
  'od_session_id',
  'od_cancel_session',
  'od_reset_cancel',
  'od_cancelled',
  'od_gpu_device_count',
  'od_cpu_isa',
];

/// What the loader needs from the engine updater: the installed pack's folder
/// and the crash markers written around a load from it.
abstract class EnginePackLoader {
  /// Engines root as a plain path, so a worker isolate can rebuild this.
  String? get rootPath;

  int? get cudaMajor;

  List<String> get unavailableFiles => const [];

  /// Folder holding the active pack's DLLs, or null for the bundled engine.
  String? activePackDir();

  /// Called before a load from the pack and after it succeeded again: two
  /// loads that never finished revert to the bundled engine.
  void markLoadStarted();
  void markLoadSucceeded();
}

/// Tracks a pack attempt across bridge initialization and model loading.
/// Opening exports alone must never clear the persisted crash count.
class EnginePackLoadGuard {
  final EnginePackLoader loader;
  bool _prepared = false;
  bool selected = false;
  EnginePackLoadGuard(this.loader);

  void beforeOpen() {
    if (_prepared) return;
    loader.markLoadStarted();
    _prepared = true;
  }

  void beforeModelLoad() {
    if (!selected) return;
    if (!_prepared) loader.markLoadStarted();
    _prepared = false;
  }

  void modelLoadSucceeded() {
    if (selected) loader.markLoadSucceeded();
  }
}

/// Only binds our stable ABI. Upstream structs stay in C++.
class LlamaBindings {
  static const supportedAbi = 7;

  /// The fast CPU bridge is independent of the optional OpenCL driver.
  /// OpenCL builds retain GPU support; CPU-only builds still get the same
  /// Armv8.6+dotprod+i8mm+fp16 kernels on arm64, or AVX2 kernels on x86_64.
  /// Older CPUs use the portable bridge (Armv8-A, or baseline x86-64).
  /// The selected library and skipped candidates are recorded in metrics.
  static const androidVariants = [
    'libondevice_llm_opencl.so',
    'libondevice_llm_cpu_avx2.so',
    'libondevice_llm_cpu_i8mm.so',
    'libondevice_llm.so',
  ];

  static bool variantNeedsI8mm(String name) =>
      name == 'libondevice_llm_opencl.so' ||
      name == 'libondevice_llm_cpu_i8mm.so';

  static bool variantNeedsAvx2(String name) =>
      name == 'libondevice_llm_cpu_avx2.so';

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
    // Probe/control bindings must not count as unfinished model loads.
    bool modelLoad = false,
  }) {
    final lib = libraryPath != null
        ? (libraryPath == 'process' ? _process() : _open(libraryPath))
        : Platform.isAndroid
        ? _openAndroid()
        : Platform.isWindows
        ? _openWindows(windowsBackend, cpuVariant, modelLoad)
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
    if (lib.providesSymbol('od_side_open')) {
      sideOpen = lib
          .lookupFunction<
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>),
            Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)
          >('od_side_open');
      sideSubmit = lib
          .lookupFunction<
            Int32 Function(Pointer<Void>, Int32, Pointer<Utf8>),
            int Function(Pointer<Void>, int, Pointer<Utf8>)
          >('od_side_submit');
      sideStep = lib
          .lookupFunction<
            Pointer<Utf8> Function(Pointer<Void>),
            Pointer<Utf8> Function(Pointer<Void>)
          >('od_side_step');
      sideCancel = lib
          .lookupFunction<
            Void Function(Pointer<Void>, Int32),
            void Function(Pointer<Void>, int)
          >('od_side_cancel');
      sideClose = lib
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('od_side_close');
    }
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

  EnginePackLoadGuard? _packLoadGuard;

  void markModelLoadStarted() => _packLoadGuard?.beforeModelLoad();
  void markModelLoadSucceeded() => _packLoadGuard?.modelLoadSucceeded();

  DynamicLibrary _open(String name) {
    // Assign only after success: `library` is final and a failed variant
    // must not claim it.
    final path = Platform.isWindows ? windowsBridgePath(name) : name;
    final lib = DynamicLibrary.open(path);
    library = path;
    return lib;
  }

  /// Installed by the engine updater; null on Android and in tests, where
  /// only the bundled DLLs exist.
  static EnginePackLoader? enginePack;

  /// CUDA, then hardware Vulkan, then CPU. Overrides try only that GPU.
  DynamicLibrary _openWindows(
    String? preferred,
    String cpuVariant,
    bool modelLoad,
  ) {
    final pack = enginePack;
    final packDir = pack?.activePackDir();
    if (packDir != null) _packLoadGuard = EnginePackLoadGuard(pack!);
    final selected = openWindowsLibrary<DynamicLibrary>(
      skipped: skipped,
      preferred: preferred,
      cpuVariant: cpuVariant,
      packDir: packDir,
      packCudaMajor: pack?.cudaMajor,
      unavailablePackFiles: pack?.unavailableFiles ?? const [],
      open: (name) {
        // Only actual pack attempts count. Known-unavailable GPU variants
        // may use bundled DLLs without penalizing the pack's crash guard.
        if (modelLoad && packDir != null && name.startsWith(packDir)) {
          _packLoadGuard!.beforeOpen();
        }
        return DynamicLibrary.open(name);
      },
      checkEngineFiles: EngineFiles.besideExecutable().checkVariant,
      gpuDeviceCount: (lib) =>
          lib.lookupFunction<Int32 Function(), int Function()>(
            'od_gpu_device_count',
          )(),
    );
    // A bundled fallback leaves the failed pack attempt counted.
    _packLoadGuard?.selected =
        packDir != null && selected.name.startsWith(packDir);
    library = selected.name;
    return selected.handle;
  }

  /// The GPU backend of an opened Windows bridge name ('vulkan' for
  /// ondevice_llm_vulkan.dll), so another isolate can open the same DLL;
  /// null for the CPU bridge and other platforms. A full engine pack path
  /// matches on its file name part.
  static String? windowsGpuOf(String? library) {
    final file = _fileName(library);
    if (file.contains('_vulkan')) return 'vulkan';
    if (file.contains('_cuda')) return 'cuda';
    return null;
  }

  /// Windows checks both CPU support and OS AVX state management.
  static bool windowsHasAvx2() {
    final present = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Int32 Function(Uint32), int Function(int)>(
          'IsProcessorFeaturePresent',
        );
    // PF_AVX2_INSTRUCTIONS_AVAILABLE, then FMA/F16C/BMI2 too.
    return present(40) != 0 && (_windowsIsa ?? 1) & 1 != 0;
  }

  static bool windowsHasAvx512() {
    final present = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<Int32 Function(Uint32), int Function(int)>(
          'IsProcessorFeaturePresent',
        );
    // PF_AVX512F_INSTRUCTIONS_AVAILABLE, then CD/BW/DQ/VL too.
    return present(41) != 0 && (_windowsIsa ?? 2) & 2 != 0;
  }

  /// od_cpu_isa from the SSE4.2 bridge (safe on any x86-64 CPU): Windows'
  /// own flags cover AVX2 and AVX-512F only, while the bridges also use
  /// FMA, F16C, BMI2 and AVX-512 CD/BW/DQ/VL (audit 2026-11-16 AUD-003).
  /// Null when the bridge or its export is missing: the OS flags decide.
  static final int? _windowsIsa = () {
    try {
      final dir = enginePack?.activePackDir();
      final path = dir == null ? null : '$dir\\ondevice_llm_compat.dll';
      final lib = DynamicLibrary.open(
        path != null && File(path).existsSync()
            ? path
            : windowsBridgePath('ondevice_llm_compat.dll'),
      );
      return lib.lookupFunction<Int32 Function(), int Function()>(
        'od_cpu_isa',
      )();
    } catch (_) {
      return null;
    }
  }();

  static String? windowsCpuOf(String? library) => switch (_fileName(library)) {
    'ondevice_llm_avx512.dll' => 'avx512',
    'ondevice_llm.dll' => 'avx2',
    'ondevice_llm_compat.dll' => 'compat',
    _ => null,
  };

  /// File name part of a bridge name or of a full path to it, lower case.
  static String _fileName(String? library) =>
      (library ?? '').split(RegExp(r'[\\/]')).last.toLowerCase();

  /// Absolute bundled paths avoid Windows reusing a mapped pack by basename.
  /// Also used when a worker isolate reopens an explicitly selected bridge.
  static String windowsBridgePath(String name, {String? executableDirectory}) {
    if (name.contains(RegExp(r'[\\/]'))) return name;
    return '${executableDirectory ?? File(Platform.resolvedExecutable).parent.path}\\$name';
  }

  // Set from the paired local hardware smoke measurements.
  static const autoAvx512 = false;

  /// Injectable OS and loader checks keep tests independent of host hardware.
  /// [packDir] is the folder of an installed engine pack: its DLLs are tried
  /// before the bundled ones, and their hashes were verified at install so the
  /// damage check applies only to the bundled files.
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
    String? packDir,
    String? executableDirectory,
    int? packCudaMajor,
    List<String> unavailablePackFiles = const [],
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
    // The pack copy of [name], or null when the active pack has no such DLL.
    String? packPath(String name) {
      if (packDir == null) return null;
      if (unavailablePackFiles.contains(name.toLowerCase())) {
        skipped.add('$name: engine pack variant unavailable; using bundled');
        return null;
      }
      if (name.contains('_cuda') &&
          packCudaMajor != null &&
          !exists(
            '${File(Platform.resolvedExecutable).parent.path}\\cudart64_$packCudaMajor.dll',
          )) {
        skipped.add('$name: engine pack requires CUDA $packCudaMajor');
        return null;
      }
      final path = '$packDir\\$name';
      return exists(path) ? path : null;
    }

    // The pack copy first, then the bundled file after its damage check.
    // A null bridge means neither copy opened, and [failure] is the last open
    // error; a damaged bundled file reports null with no failure.
    ({({String name, T handle})? bridge, Object? failure}) candidate(
      String name, {
      String openFailure = '',
    }) {
      final path = packPath(name);
      if (path != null) {
        try {
          return (bridge: (name: path, handle: open(path)), failure: null);
        } catch (e) {
          skipped.add(
            '$name: engine pack copy failed ($e); using the bundled copy',
          );
        }
      }
      final damaged =
          checkEngineFiles?.call(name) ?? const <EngineFileResult>[];
      if (damaged.isNotEmpty) {
        skipped.add(
          '$name: ${damaged.map((r) => '${r.name} (${r.status.name})').join(', ')}',
        );
        return (bridge: null, failure: null);
      }
      try {
        final bundled = windowsBridgePath(
          name,
          executableDirectory: executableDirectory,
        );
        return (bridge: (name: bundled, handle: open(bundled)), failure: null);
      } catch (e) {
        skipped.add('$name: $e$openFailure');
        return (bridge: null, failure: e);
      }
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
      final ({String name, T handle})? bridge = candidate(name).bridge;
      if (bridge == null) continue;
      try {
        if (gpuDeviceCount(bridge.handle) <= 0) {
          skipped.add(
            nvidia
                ? '$name: no GPU this CUDA runtime can use (driver too old?)'
                : '$name: no hardware GPU devices',
          );
          continue;
        }
      } catch (e) {
        skipped.add('$name: $e');
        continue;
      }
      return bridge;
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
      final result = candidate(
        name,
        openFailure: '; trying the next CPU variant',
      );
      if (result.failure != null) failure = result.failure;
      final bridge = result.bridge;
      if (bridge != null) return bridge;
    }
    throw StateError('No usable CPU bridge: $failure; ${skipped.join('; ')}');
  }

  DynamicLibrary _process() {
    library = 'process';
    return DynamicLibrary.process();
  }

  /// The fast arm64 variant is compiled for armv8.6+i8mm; a CPU without i8mm
  /// would hit SIGILL, which no catch can recover, so check first.
  /// [cpuinfo] replaces /proc/cpuinfo in tests.
  static bool cpuHasI8mm({String? cpuinfo}) => _everyCpuFlag(
    cpuinfo,
    RegExp(r'^Features\s*:\s*(.*)$', multiLine: true),
    'i8mm',
  );

  /// The fast x86_64 variant is compiled for AVX, AVX2, FMA, F16C and BMI2
  /// (native/CMakeLists.txt, ODLLM_X64_FAST); a CPU missing any of them would
  /// hit SIGILL, so check them all first. False on arm64 (no flags line) and
  /// in tests that pass an empty or partial cpuinfo.
  static bool cpuHasAvx2({String? cpuinfo}) =>
      const ['avx', 'avx2', 'fma', 'f16c', 'bmi2'].every(
        (flag) => _everyCpuFlag(
          cpuinfo,
          RegExp(r'^flags\s*:\s*(.*)$', multiLine: true),
          flag,
        ),
      );

  /// Every core lists its own feature line and the fast library runs on
  /// whichever core the scheduler picks, so all of them must have [flag].
  /// A cpuinfo without a matching line (arm64 on x86, or x86 on arm64)
  /// counts as unsupported.
  static bool _everyCpuFlag(String? cpuinfo, RegExp line, String flag) {
    try {
      final info = cpuinfo ?? File('/proc/cpuinfo').readAsStringSync();
      final lines = line.allMatches(info).toList();
      if (lines.isEmpty) return false;
      return lines.every(
        (m) => m.group(1)!.trim().split(RegExp(r'\s+')).contains(flag),
      );
    } catch (_) {
      return false;
    }
  }

  static String? _readCpuinfo() {
    try {
      return File('/proc/cpuinfo').readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  /// Why [name] cannot run on this CPU, or null when it may be loaded.
  static String? _unmetVariant(String name, String? cpuinfo) {
    if (variantNeedsI8mm(name) && !cpuHasI8mm(cpuinfo: cpuinfo)) {
      return 'this CPU lacks i8mm';
    }
    if (variantNeedsAvx2(name) && !cpuHasAvx2(cpuinfo: cpuinfo)) {
      return 'this CPU lacks AVX2';
    }
    return null;
  }

  DynamicLibrary _openAndroid() {
    final cpuinfo = _readCpuinfo();
    Object? last;
    for (final name in androidVariants) {
      final unmet = _unmetVariant(name, cpuinfo);
      if (unmet != null) {
        skipped.add('$name: $unmet');
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

  Pointer<Void> Function(Pointer<Void>, Pointer<Utf8>)? sideOpen;
  int Function(Pointer<Void>, int, Pointer<Utf8>)? sideSubmit;
  Pointer<Utf8> Function(Pointer<Void>)? sideStep;
  void Function(Pointer<Void>, int)? sideCancel;
  void Function(Pointer<Void>)? sideClose;
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
