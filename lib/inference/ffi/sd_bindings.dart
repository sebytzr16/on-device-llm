import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

import 'llama_bindings.dart';

/// FFI bindings for the stable-diffusion.cpp bridge, built by
/// scripts/build-windows-sd.ps1 into native/out/windows-x64/ in up to three
/// variants (GitHub issue #4: a host-tuned build ran AVX-512 on AVX2 CPUs):
/// - ondevice_sd.dll: NVIDIA CUDA, AVX2 CPU code (needs nvcuda.dll);
/// - ondevice_sd_cpu.dll: CPU only, AVX2/FMA/F16C;
/// - ondevice_sd_compat.dll: CPU only, SSE4.2 (no AVX).
class SdBindings {
  static const _sdDllName = 'ondevice_sd.dll';
  static const cpuDllName = 'ondevice_sd_cpu.dll';
  static const compatDllName = 'ondevice_sd_compat.dll';
  static const allDllNames = [_sdDllName, cpuDllName, compatDllName];
  static const supportedVersion = 4;

  /// The DLL this instance opened.
  late final String library;

  /// The variants to try in order. [cpuVariant] is the desktop CPU setting
  /// ('auto', 'avx512', 'avx2', 'compat'): 'compat' forces the SSE4.2 build.
  /// The CUDA build needs AVX2 and the NVIDIA driver; every AVX build needs
  /// AVX2 reported by Windows.
  static List<String> candidates({
    String cpuVariant = 'auto',
    bool Function()? hasAvx2,
    bool Function(String)? exists,
    Map<String, String>? environment,
  }) {
    final has = exists ?? _exists;
    final env = environment ?? Platform.environment;
    final root = env['SystemRoot'] ?? r'C:\Windows';
    final override = env['ODLLM_WINDOWS_BACKEND']?.trim().toLowerCase();
    final compatOnly = cpuVariant == 'compat' || override == 'compat';
    final avx2 = !compatOnly && (hasAvx2 ?? LlamaBindings.windowsHasAvx2)();
    final cpuOnly = override == 'cpu' || override == 'vulkan';
    final nvidia = has('$root\\System32\\nvcuda.dll');
    return [
      if (avx2 && !cpuOnly && nvidia) _sdDllName,
      if (avx2) cpuDllName,
      compatDllName,
    ].where(has).toList();
  }

  static bool _exists(String name) =>
      File(name).existsSync() || File('$_exeDir$name').existsSync();

  static String get _exeDir =>
      Platform.resolvedExecutable.replaceFirst(RegExp(r'[^\\/]+$'), '');

  late final Pointer<Void> Function(Pointer<Utf8>) create;
  late final void Function(Pointer<Void>) destroy;
  late final int Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
    Pointer<Utf8>,
  )
  load;
  late final Pointer<Utf8> Function(Pointer<Void>) error;
  late final Pointer<Uint8> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<NativeFunction<SdProgressFn>>,
    Pointer<Void>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  txt2img;

  /// od_sd_img2img: [txt2img]'s arguments with the RGBA starting picture and
  /// its size after the request.
  late final Pointer<Uint8> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<NativeFunction<SdProgressFn>>,
    Pointer<Void>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  img2img;
  late final Pointer<Uint8> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<NativeFunction<SdProgressFn>>,
    Pointer<Void>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  txt2vid;
  late final int Function(Pointer<Utf8>, Pointer<Uint8>, int, int, int, int)
  saveVideo;
  late final Pointer<Uint8> Function(
    Pointer<Void>,
    Pointer<Utf8>,
    Pointer<Uint8>,
    int,
    int,
    int,
    Pointer<Int32>,
    Pointer<Int32>,
  )
  upscale;
  late final void Function(Pointer<Uint8>) freeImage;
  late final void Function(Pointer<Void>) cancel;

  late final void Function(Pointer<Void>) resetCancel;

  /// Opens [only] when given (the worker's choice, so another isolate uses
  /// the same DLL), else the first of [candidates] that loads.
  SdBindings({String cpuVariant = 'auto', String? only}) {
    if (!Platform.isWindows) {
      throw UnsupportedError('SdBindings is Windows-only for now.');
    }
    final names = only != null ? [only] : candidates(cpuVariant: cpuVariant);
    if (names.isEmpty) {
      throw StateError(
        'No image engine for this PC: none of ${allDllNames.join(', ')} '
        'is installed',
      );
    }
    DynamicLibrary? opened;
    final failures = <String>[];
    for (final name in names) {
      try {
        opened = DynamicLibrary.open(name);
        library = name;
        break;
      } catch (e) {
        // ondevice_sd.dll fails here when the CUDA runtime is missing.
        failures.add('$name: $e');
      }
    }
    if (opened == null) throw StateError(failures.join('; '));
    final lib = opened;
    final version = lib.lookupFunction<Int32 Function(), int Function()>(
      'od_sd_version',
    );
    if (version() != supportedVersion) {
      throw StateError(
        'Unsupported sd bridge version ${version()}; expected $supportedVersion',
      );
    }
    resetCancel = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('od_sd_reset_cancel');
    create = lib
        .lookupFunction<
          Pointer<Void> Function(Pointer<Utf8>),
          Pointer<Void> Function(Pointer<Utf8>)
        >('od_sd_create');
    destroy = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('od_sd_destroy');
    load = lib
        .lookupFunction<
          Int32 Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
          ),
          int Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
          )
        >('od_sd_load');
    error = lib
        .lookupFunction<
          Pointer<Utf8> Function(Pointer<Void>),
          Pointer<Utf8> Function(Pointer<Void>)
        >('od_sd_error');
    txt2img = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<NativeFunction<SdProgressFn>>,
            Pointer<Void>,
            Pointer<Int32>,
            Pointer<Int32>,
          ),
          Pointer<Uint8> Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<NativeFunction<SdProgressFn>>,
            Pointer<Void>,
            Pointer<Int32>,
            Pointer<Int32>,
          )
        >('od_sd_txt2img');
    img2img = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Uint8>,
            Int32,
            Int32,
            Pointer<NativeFunction<SdProgressFn>>,
            Pointer<Void>,
            Pointer<Int32>,
            Pointer<Int32>,
          ),
          Pointer<Uint8> Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Uint8>,
            int,
            int,
            Pointer<NativeFunction<SdProgressFn>>,
            Pointer<Void>,
            Pointer<Int32>,
            Pointer<Int32>,
          )
        >('od_sd_img2img');
    txt2vid = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Uint8>,
            Int32,
            Int32,
            Pointer<NativeFunction<SdProgressFn>>,
            Pointer<Void>,
            Pointer<Int32>,
            Pointer<Int32>,
            Pointer<Int32>,
            Pointer<Int32>,
          ),
          Pointer<Uint8> Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Uint8>,
            int,
            int,
            Pointer<NativeFunction<SdProgressFn>>,
            Pointer<Void>,
            Pointer<Int32>,
            Pointer<Int32>,
            Pointer<Int32>,
            Pointer<Int32>,
          )
        >('od_sd_txt2vid');
    saveVideo = lib
        .lookupFunction<
          Int32 Function(
            Pointer<Utf8>,
            Pointer<Uint8>,
            Int32,
            Int32,
            Int32,
            Int32,
          ),
          int Function(Pointer<Utf8>, Pointer<Uint8>, int, int, int, int)
        >('od_sd_save_video');
    upscale = lib
        .lookupFunction<
          Pointer<Uint8> Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Uint8>,
            Int32,
            Int32,
            Int32,
            Pointer<Int32>,
            Pointer<Int32>,
          ),
          Pointer<Uint8> Function(
            Pointer<Void>,
            Pointer<Utf8>,
            Pointer<Uint8>,
            int,
            int,
            int,
            Pointer<Int32>,
            Pointer<Int32>,
          )
        >('od_sd_upscale');
    freeImage = lib
        .lookupFunction<
          Void Function(Pointer<Uint8>),
          void Function(Pointer<Uint8>)
        >('od_sd_free_image');
    cancel = lib
        .lookupFunction<
          Void Function(Pointer<Void>),
          void Function(Pointer<Void>)
        >('od_sd_cancel');
  }

  /// Widget tests set this to show the Create page without the DLL.
  static bool? debugAvailable;

  /// Returns true if the sd DLL is present beside the executable.
  static bool isAvailable() {
    if (debugAvailable != null) return debugAvailable!;
    if (!Platform.isWindows) return false;
    return candidates().isNotEmpty;
  }
}

/// C callback signature: void progress(int32_t step, int32_t total, void* user_data)
typedef SdProgressFn = Void Function(Int32, Int32, Pointer<Void>);
