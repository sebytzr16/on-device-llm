import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows: ties helper processes (DiffusionGemma's host, MCP servers) to
/// the app, so they die with it even when it crashes or is killed from
/// Task Manager. The job handle is never closed; Windows closes it when the
/// app exits, and kill-on-close then ends every process in the job.
///
/// Only processes added here join: files opened in other apps stay open.
abstract final class ChildProcessJob {
  static int? _job;
  static bool _failed = false;

  /// Adds [process] to the job. Best effort: a failure leaves it running
  /// as before, and other platforms do nothing.
  static void adopt(Process process) {
    if (!Platform.isWindows || _failed) return;
    try {
      final job = _job ??= _create();
      final handle = _openProcess(
        _processSetQuota | _processTerminate,
        0,
        process.pid,
      );
      if (handle == 0) return;
      _assign(job, handle);
      _closeHandle(handle);
    } catch (_) {
      _failed = true;
    }
  }

  static int _create() {
    final job = _createJob(nullptr, nullptr);
    if (job == 0) throw StateError('CreateJobObject failed');
    // JOBOBJECT_EXTENDED_LIMIT_INFORMATION is 144 bytes on 64-bit Windows;
    // BasicLimitInformation.LimitFlags sits at offset 16.
    final info = calloc<Uint8>(144);
    try {
      (info + 16).cast<Uint32>().value = _killOnJobClose;
      if (_setInformation(job, _extendedLimitInformation, info.cast(), 144) ==
          0) {
        _closeHandle(job);
        throw StateError('SetInformationJobObject failed');
      }
    } finally {
      calloc.free(info);
    }
    return job;
  }

  static const _extendedLimitInformation = 9;
  static const _killOnJobClose = 0x2000;
  static const _processSetQuota = 0x0100;
  static const _processTerminate = 0x0001;

  static final _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final _createJob = _kernel32
      .lookupFunction<
        IntPtr Function(Pointer<Void>, Pointer<Utf16>),
        int Function(Pointer<Void>, Pointer<Utf16>)
      >('CreateJobObjectW');
  static final _setInformation = _kernel32
      .lookupFunction<
        Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('SetInformationJobObject');
  static final _openProcess = _kernel32
      .lookupFunction<
        IntPtr Function(Uint32, Int32, Uint32),
        int Function(int, int, int)
      >('OpenProcess');
  static final _assign = _kernel32
      .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>(
        'AssignProcessToJobObject',
      );
  static final _closeHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
}
