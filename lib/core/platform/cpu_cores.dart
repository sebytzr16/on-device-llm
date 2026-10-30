import 'dart:ffi';
import 'dart:io';

/// CPU cores for the desktop thread defaults: llama.cpp's own count of
/// physical cores (od_cpu_cores), since the second thread of an SMT core
/// slows prompt reading down (16 threads on an 8-core laptop took a
/// 12-token first message from 0.3 s to 6.6 s, 2026-10-27).
abstract final class CpuCores {
  /// Physical cores; null until first asked, or when the bridge cannot say.
  static int? physical;
  static var _asked = false;

  /// Logical processors; injectable in tests.
  static int Function() logical = () => Platform.numberOfProcessors;

  /// Asks the bridge once; injectable in tests.
  static int? Function() query = _fromBridge;

  /// Physical cores, or half the logical ones on a machine of 8 or more.
  static int get desktop {
    if (physical == null && !_asked) {
      _asked = true;
      physical = query();
    }
    final count = logical();
    return physical ?? (count >= 8 ? count ~/ 2 : count);
  }

  /// The plain CPU bridge answers without starting a GPU runtime (the CUDA
  /// one would initialise CUDA just to count cores).
  static int? _fromBridge() {
    if (!Platform.isWindows) return null;
    for (final name in const ['ondevice_llm_compat.dll', 'ondevice_llm.dll']) {
      try {
        final cores = DynamicLibrary.open(
          name,
        ).lookupFunction<Int32 Function(), int Function()>('od_cpu_cores')();
        if (cores > 0) return cores;
      } catch (_) {}
    }
    return null;
  }
}
