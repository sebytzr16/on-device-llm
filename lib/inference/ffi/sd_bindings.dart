import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// FFI bindings for ondevice_sd.dll (stable-diffusion.cpp bridge).
/// The DLL is built by scripts/build-windows-sd.ps1 and staged at
/// native/out/windows-x64/ondevice_sd.dll.
class SdBindings {
  static const _sdDllName = 'ondevice_sd.dll';
  static const supportedVersion = 4;

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

  SdBindings() {
    if (!Platform.isWindows) {
      throw UnsupportedError('SdBindings is Windows-only for now.');
    }
    final lib = DynamicLibrary.open(_sdDllName);
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

  /// Returns true if the sd DLL is present beside the executable.
  static bool isAvailable() {
    if (!Platform.isWindows) return false;
    return File(_sdDllName).existsSync() ||
        File(
          '${Platform.resolvedExecutable.replaceFirst(RegExp(r'[^\\/]+$'), '')}$_sdDllName',
        ).existsSync();
  }
}

/// C callback signature: void progress(int32_t step, int32_t total, void* user_data)
typedef SdProgressFn = Void Function(Int32, Int32, Pointer<Void>);
