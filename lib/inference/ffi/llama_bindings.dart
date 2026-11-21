import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import '../../desktop/engine_files.dart';
import '../engine/engine_descriptor.dart';

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

  /// Folder whose DLLs match an authenticated installed manifest.
  String? verifiedPackDir();

  /// The signed manifest's SHA-256 for [name] of the verified pack [dir], or
  /// null when that pack does not list the file. The loader re-hashes a pack
  /// bridge against it while holding a no-write/no-delete lock on the file.
  String? expectedFileSha256(String dir, String name);

  /// Called before a load from the pack and after it succeeded again: two
  /// loads that never finished revert to the bundled engine. Returns false
  /// when the attempt could not be recorded: the load must then refuse the
  /// pack instead of running unguarded.
  bool markLoadStarted();
  void markLoadSucceeded();
}

/// Tracks a pack attempt across bridge initialization and model loading.
/// Opening exports alone must never clear the persisted crash count.
class EnginePackLoadGuard {
  final EnginePackLoader loader;
  bool _prepared = false;
  bool selected = false;
  EnginePackLoadGuard(this.loader);

  /// Records the attempt; throws when the crash state could not be written,
  /// so the caller refuses the pack for this load instead of running it with
  /// a crash guard that cannot notice a crash loop.
  void _markStarted() {
    if (!loader.markLoadStarted()) {
      throw StateError(
        'The engine pack crash guard could not record this load; '
        'refusing the pack for this load',
      );
    }
  }

  void beforeOpen() {
    if (_prepared) return;
    _markStarted();
    _prepared = true;
  }

  void beforeModelLoad() {
    if (!selected) return;
    if (!_prepared) _markStarted();
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
  /// [engineId] picks the engine whose pack the DLLs come from; llama.cpp's
  /// bundled DLLs are never used for another engine.
  /// [libraryPath] reopens a worker's already selected library without probing.
  LlamaBindings({
    String? windowsBackend,
    String cpuVariant = 'auto',
    String? libraryPath,
    String engineId = llamaCppEngineId,
    // Probe/control bindings must not count as unfinished model loads.
    bool modelLoad = false,
  }) {
    final lib = libraryPath != null
        ? (libraryPath == 'process' ? _process() : _open(libraryPath))
        : Platform.isAndroid
        ? _openAndroid()
        : Platform.isWindows
        ? _openWindows(windowsBackend, cpuVariant, modelLoad, engineId)
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
    final lib = Platform.isWindows
        ? WindowsBridgeLoader.reopen(path)
        : DynamicLibrary.open(path);
    library = path;
    return lib;
  }

  /// Installed by the engine updater; null on Android and in tests, where
  /// only the bundled DLLs exist. [ikEnginePack] is the optional ik_llama.cpp
  /// pack: it lives in its own folder and has no bundled fallback.
  static EnginePackLoader? enginePack;
  static EnginePackLoader? ikEnginePack;

  /// The signed manifest's digest for the pack bridge [name] of [dir]. A file
  /// the manifest does not list has none: the open refuses it instead of
  /// mapping an unverified pack file (P1-1). Bundled DLLs never get here.
  static String packBridgeSha256(
    EnginePackLoader? pack,
    String dir,
    String name,
  ) {
    final digest = pack?.expectedFileSha256(dir, name);
    if (digest == null) {
      throw StateError(
        '$name is not listed in the signed manifest of the engine pack '
        '$dir; refusing to load it unverified',
      );
    }
    return digest;
  }

  /// CUDA, then hardware Vulkan, then CPU. Overrides try only that GPU.
  DynamicLibrary _openWindows(
    String? preferred,
    String cpuVariant,
    bool modelLoad,
    String engineId,
  ) {
    final ik = engineId == ikLlamaEngineId;
    final pack = ik ? ikEnginePack : enginePack;
    final packDir = pack?.verifiedPackDir();
    if (ik && packDir == null) {
      throw StateError(
        'OD_IK_LOAD_FAILED: the ik_llama.cpp engine pack is not installed',
      );
    }
    if (packDir != null) _packLoadGuard = EnginePackLoadGuard(pack!);
    int? isa;
    var probedIsa = false;
    int? readIsa() {
      if (!probedIsa) {
        probedIsa = true;
        isa = _windowsIsaIn(
          modelLoad ? packDir : null,
          allowBundled: !modelLoad || !ik,
          // The probe maps the pack's own compat bridge, so it is a pack
          // attempt of this model load for every engine (P3-4). The callback
          // only runs when the pack copy exists.
          beforePackOpen: () => _packLoadGuard!.beforeOpen(),
          expectedSha256: !modelLoad || packDir == null
              ? null
              : pack?.expectedFileSha256(packDir, 'ondevice_llm_compat.dll'),
        );
      }
      return isa;
    }

    final ({String name, DynamicLibrary handle}) selected;
    try {
      selected = openWindowsLibrary<DynamicLibrary>(
        skipped: skipped,
        preferred: preferred,
        cpuVariant: cpuVariant,
        packDir: packDir,
        hasAvx2: () =>
            _processorFeaturePresent(40) != 0 && (readIsa() ?? 1) & 1 != 0,
        hasAvx512: () =>
            _processorFeaturePresent(41) != 0 && (readIsa() ?? 2) & 2 != 0,
        packCudaMajor: packDir == null ? null : pack?.cudaMajor,
        unavailablePackFiles: pack?.unavailableFiles ?? const [],
        // Another engine's pack is the only source of its bridge: a failed
        // open is reported, never answered with llama.cpp's DLLs.
        allowBundledFallback: !ik,
        open: (name) {
          // Only actual pack attempts count. Known-unavailable GPU variants
          // may use bundled DLLs without penalizing the pack's crash guard.
          final dir = packDir;
          if (dir != null && p.windows.equals(p.windows.dirname(name), dir)) {
            if (modelLoad) _packLoadGuard!.beforeOpen();
            // A pack file the signed manifest does not list has no digest and
            // is refused here instead of being mapped unverified (P1-1).
            return WindowsBridgeLoader.open(
              name,
              expectedSha256: packBridgeSha256(
                pack,
                dir,
                p.windows.basename(name),
              ),
            );
          }
          return WindowsBridgeLoader.open(name);
        },
        checkEngineFiles: EngineFiles.besideExecutable().checkVariant,
        gpuDeviceCount: (lib) =>
            lib.lookupFunction<Int32 Function(), int Function()>(
              'od_gpu_device_count',
            )(),
      );
    } on StateError catch (e) {
      if (!ik) rethrow;
      throw StateError('OD_IK_LOAD_FAILED: ${e.message}');
    }
    // A bundled fallback leaves the failed pack attempt counted.
    _packLoadGuard?.selected =
        packDir != null &&
        p.windows.equals(p.windows.dirname(selected.name), packDir);
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

  static final _processorFeaturePresent = WindowsBridgeLoader._kernel32
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'IsProcessorFeaturePresent',
      );

  /// Windows flags cover AVX2 and AVX-512F. The compat bridge also checks
  /// FMA, F16C, BMI2 and AVX-512 CD/BW/DQ/VL.
  static bool windowsHasAvx2() =>
      _processorFeaturePresent(40) != 0 && (windowsProbeIsa() ?? 1) & 1 != 0;

  static bool windowsHasAvx512() =>
      _processorFeaturePresent(41) != 0 && (windowsProbeIsa() ?? 2) & 2 != 0;

  /// Standalone hardware probes use the bundled compat bridge. Model loads
  /// probe pack bridges in the crash-accounted path above.
  static int? windowsProbeIsa({int Function(String)? readIsa}) =>
      _windowsIsaIn(null, readIsa: readIsa);

  static int? _windowsIsaIn(
    String? packDir, {
    bool allowBundled = true,
    void Function()? beforePackOpen,
    String? expectedSha256,
    int Function(String)? readIsa,
  }) {
    const compat = 'ondevice_llm_compat.dll';
    final path = packDir == null ? null : p.windows.join(packDir, compat);
    try {
      final String bridge;
      if (path != null && File(path).existsSync()) {
        // A pack copy the signed manifest does not list has no digest: it is
        // never opened unverified (P1-1).
        if (expectedSha256 == null) return null;
        beforePackOpen?.call();
        bridge = path;
      } else {
        if (!allowBundled) return null;
        bridge = windowsBridgePath(compat);
      }
      if (readIsa != null) return readIsa(bridge);
      return WindowsBridgeLoader.open(
        bridge,
        expectedSha256: bridge == path ? expectedSha256 : null,
      ).lookupFunction<Int32 Function(), int Function()>('od_cpu_isa')();
    } catch (_) {
      return null;
    }
  }

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
  /// [allowBundledFallback] false makes the pack the only source, for an
  /// engine that has no bundled copy.
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
    bool allowBundledFallback = true,
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
            allowBundledFallback
                ? '$name: engine pack copy failed ($e); using the bundled copy'
                : '$name: engine pack copy failed ($e)',
          );
        }
      }
      if (!allowBundledFallback) {
        skipped.add('$name: the engine pack does not provide it');
        return (bridge: null, failure: null);
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

/// Restricted Windows loads for both bridge selection and the ISA probe.
///
/// A pack bridge is never opened with `DynamicLibrary.open` directly: that
/// bypasses the restricted search path, and the loader must be able to lock
/// and re-hash the file first. Always go through [open].
abstract final class WindowsBridgeLoader {
  static const _searchDllLoadDir = 0x00000100;
  static const _searchApplicationDir = 0x00000200;
  static const _searchSystem32 = 0x00000800;

  static const _genericRead = 0x80000000;
  // Only readers may open the file: no writer and no deleter.
  static const _fileShareRead = 0x00000001;
  static const _openExisting = 3;
  static const _fileAttributeNormal = 0x80;

  // kernel32.dll is a Windows Known DLL.
  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _loadLibraryEx = _kernel32
      .lookupFunction<
        Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, Uint32),
        Pointer<Void> Function(Pointer<Utf16>, Pointer<Void>, int)
      >('LoadLibraryExW');
  static final _freeLibrary = _kernel32
      .lookupFunction<
        Int32 Function(Pointer<Void>),
        int Function(Pointer<Void>)
      >('FreeLibrary');
  static final _getModuleHandleEx = _kernel32
      .lookupFunction<
        Int32 Function(Uint32, Pointer<Utf16>, Pointer<Pointer<Void>>),
        int Function(int, Pointer<Utf16>, Pointer<Pointer<Void>>)
      >('GetModuleHandleExW');
  // CreateFileW and CloseHandle hand back and take a HANDLE; IntPtr keeps the
  // INVALID_HANDLE_VALUE (-1) comparison signed and portable.
  static final _createFile = _kernel32
      .lookupFunction<
        IntPtr Function(
          Pointer<Utf16>,
          Uint32,
          Uint32,
          Pointer<Void>,
          Uint32,
          Uint32,
          Pointer<Void>,
        ),
        int Function(
          Pointer<Utf16>,
          int,
          int,
          Pointer<Void>,
          int,
          int,
          Pointer<Void>,
        )
      >('CreateFileW');
  static final _closeHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  /// Loads [path]. A pack bridge passes the SHA-256 its signed manifest lists:
  /// the file is then opened with a read-only share mode that denies every
  /// writer and deleter, hashed again while that lock is held, and only then
  /// mapped, so nothing can be swapped between the check and the load.
  static DynamicLibrary open(String path, {String? expectedSha256}) =>
      openRestricted(
        path,
        expectedSha256: expectedSha256,
        preload: (name, flags) => _loadLibraryEx(name, nullptr, flags),
        bind: DynamicLibrary.open,
        release: _freeLibrary,
      );

  /// A side/control worker may reuse an already mapped verified pack bridge.
  /// A fresh open is allowed only for a bridge beside the application.
  static DynamicLibrary reopen(String path) {
    if (p.windows.equals(
      p.windows.dirname(path),
      File(Platform.resolvedExecutable).parent.path,
    )) {
      return open(path);
    }
    _requireAbsolute(path);
    final name = path.toNativeUtf16();
    final module = calloc<Pointer<Void>>();
    try {
      if (_getModuleHandleEx(0, name, module) == 0) {
        throw ArgumentError.value(path, 'path', 'Bridge is not already mapped');
      }
      try {
        return DynamicLibrary.open(path);
      } finally {
        _freeLibrary(module.value);
      }
    } finally {
      calloc.free(module);
      calloc.free(name);
    }
  }

  static void _requireAbsolute(String path) {
    if (!p.windows.isAbsolute(path) || p.windows.rootPrefix(path).length < 3) {
      throw ArgumentError.value(
        path,
        'path',
        'Expected a fully qualified bridge path',
      );
    }
  }

  static T openRestricted<T>(
    String path, {
    required Pointer<Void> Function(Pointer<Utf16>, int) preload,
    required T Function(String) bind,
    required int Function(Pointer<Void>) release,
    String? expectedSha256,
    int Function(String)? lockForRead,
    void Function(int)? unlock,
  }) {
    _requireAbsolute(path);
    final wanted = expectedSha256?.toLowerCase();
    var lock = 0;
    if (wanted != null) {
      lock = (lockForRead ?? _lockForRead)(path);
      if (lock == _invalidHandle) {
        throw StateError('The engine pack bridge $path could not be locked');
      }
    }
    final name = path.toNativeUtf16();
    try {
      if (wanted != null && _sha256FileSync(path) != wanted) {
        throw StateError(
          'The engine pack bridge $path changed after it was verified',
        );
      }
      final module = preload(
        name,
        // A downloaded pack's directory can contain substituted dependencies.
        (wanted == null ? _searchDllLoadDir : 0) |
            _searchApplicationDir |
            _searchSystem32,
      );
      if (module == nullptr) throw StateError('Windows could not load $path');
      try {
        return bind(path);
      } finally {
        release(module);
      }
    } finally {
      calloc.free(name);
      // Held until the module is mapped and bound: a writer that got through
      // earlier is blocked here for the whole check-and-load window.
      if (lock != 0 && lock != _invalidHandle) (unlock ?? _releaseLock)(lock);
    }
  }

  static const _invalidHandle = -1;

  /// Opens [path] with read access and FILE_SHARE_READ only: every other
  /// handle that asks to write or delete fails until [unlock] closes it.
  static int _lockForRead(String path) {
    final name = path.toNativeUtf16();
    try {
      return _createFile(
        name,
        _genericRead,
        _fileShareRead,
        nullptr,
        _openExisting,
        _fileAttributeNormal,
        nullptr,
      );
    } finally {
      calloc.free(name);
    }
  }

  static void _releaseLock(int handle) => _closeHandle(handle);

  /// Streams a file through SHA-256 so a large bridge is not one Dart buffer.
  static String _sha256FileSync(String path) {
    final output = _DigestSink();
    final sink = sha256.startChunkedConversion(output);
    final input = File(path).openSync();
    try {
      final buffer = Uint8List(1 << 20);
      while (true) {
        final read = input.readIntoSync(buffer);
        if (read <= 0) break;
        sink.add(
          read == buffer.length
              ? buffer
              : Uint8List.sublistView(buffer, 0, read),
        );
      }
    } finally {
      input.closeSync();
    }
    sink.close();
    return output.value!.toString();
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
