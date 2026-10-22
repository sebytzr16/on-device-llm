import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

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

  LlamaBindings() {
    final lib = Platform.isAndroid
        ? _openAndroid()
        : Platform.isWindows
        ? _open('ondevice_llm.dll')
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
  void Function(int)? cancelSession;
  void Function(Pointer<Void>)? resetCancel;
}
