import 'dart:ffi';
import 'dart:io';
import '../../inference/ffi/llama_bindings.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

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

  /// Android big cores, using the scheduler capacity (or maximum clock).
  /// Uses the existing conservative thread default when sysfs is unavailable.
  static int get androidBig {
    final count = logical();
    if (Platform.isAndroid) {
      for (final suffix in ['cpu_capacity', 'cpufreq/cpuinfo_max_freq']) {
        try {
          final values = [
            for (var i = 0; i < count; i++)
              int.parse(
                File(
                  '/sys/devices/system/cpu/cpu$i/$suffix',
                ).readAsStringSync().trim(),
              ),
          ];
          final peak = values.reduce((a, b) => a > b ? a : b);
          return values.where((v) => v >= peak * 0.7).length.clamp(1, count);
        } catch (_) {
          // Some Android builds hide scheduler information.
        }
      }
    }
    return count >= 8 ? 6 : (count ~/ 2).clamp(2, 8);
  }

  /// The plain CPU bridge answers without starting a GPU runtime (the CUDA
  /// one would initialise CUDA just to count cores).
  static int? _fromBridge() {
    if (!Platform.isWindows) return null;
    for (final name in const ['ondevice_llm_compat.dll', 'ondevice_llm.dll']) {
      try {
        final cores = DynamicLibrary.open(
          LlamaBindings.windowsBridgePath(name),
        ).lookupFunction<Int32 Function(), int Function()>('od_cpu_cores')();
        if (cores > 0) return cores;
      } catch (e, st) {
        quietFailure('cpu_cores:39', e, st);
      }
    }
    return null;
  }
}
