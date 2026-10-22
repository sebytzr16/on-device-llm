import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Physical memory facts, read once. Used to recommend models and to pick the
/// North Star memory-pressure defaults (KV q8_0 below 8 GB, ctx 2048 below 6 GB).
class DeviceMemory {
  final int totalBytes;
  final int availableBytes;
  final bool lowMemory;
  const DeviceMemory({
    required this.totalBytes,
    required this.availableBytes,
    required this.lowMemory,
  });

  double get totalGb => totalBytes / (1024 * 1024 * 1024);

  /// Rough headroom for a model: weights plus KV cache and the app itself.
  bool fits(int modelBytes, {double minRamGb = 0}) =>
      totalGb >= minRamGb && modelBytes * 1.25 + 1.5e9 < totalBytes;

  static const _channel = MethodChannel('ondevice_llm/device');

  static Future<DeviceMemory?> read() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('memoryInfo');
      if (m == null) return null;
      return DeviceMemory(
        totalBytes: (m['totalBytes'] as num).toInt(),
        availableBytes: (m['availableBytes'] as num?)?.toInt() ?? 0,
        lowMemory: m['lowMemory'] == true,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

final deviceMemoryProvider = FutureProvider<DeviceMemory?>(
  (ref) => DeviceMemory.read(),
);

/// Ties the native model runtimes to this window (Android). Closing the app
/// destroys the window but can leave the process alive; the platform then
/// frees the models this window loaded (MainActivity.onDestroy).
class NativeOwner {
  static const _channel = MethodChannel('ondevice_llm/device');
  static Future<int>? _id;
  static final _reported = <String>{};

  /// This window's owner id; 0 where there is none (tests, other platforms).
  static Future<int> id() => _id ??= _read();

  static Future<int> _read() async {
    if (!Platform.isAndroid) return 0;
    try {
      return await _channel.invokeMethod<int>('nativeOwner') ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }

  /// Tells the platform which bridge library holds the runtimes, e.g.
  /// libondevice_llm_opencl.so, so it can reach the same copy.
  static Future<void> report(String library) async {
    if (!Platform.isAndroid || !_reported.add(library)) return;
    try {
      await _channel.invokeMethod<void>('nativeLibrary', library);
    } on PlatformException {
      _reported.remove(library);
    } on MissingPluginException {
      _reported.remove(library);
    }
  }
}

/// The display's active refresh rate in Hz (MainActivity asks for the fastest
/// mode at start-up); 0 when unknown or not Android.
class DeviceDisplay {
  static const _channel = MethodChannel('ondevice_llm/device');

  static Future<double> refreshRate() async {
    if (!Platform.isAndroid) return 0;
    try {
      return (await _channel.invokeMethod<num>('refreshRate'))?.toDouble() ?? 0;
    } on PlatformException {
      return 0;
    } on MissingPluginException {
      return 0;
    }
  }
}

final displayRefreshRateProvider = FutureProvider<double>(
  (ref) => DeviceDisplay.refreshRate(),
);

/// Space on the volume containing app-private model files.
class DeviceStorage {
  final int totalBytes;
  final int availableBytes;
  const DeviceStorage({required this.totalBytes, required this.availableBytes});

  static const _channel = MethodChannel('ondevice_llm/device');

  static Future<DeviceStorage?> read() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final data = await _channel.invokeMapMethod<String, Object?>(
        'storageInfo',
      );
      if (data == null) return null;
      return DeviceStorage(
        totalBytes: (data['totalBytes'] as num).toInt(),
        availableBytes: (data['availableBytes'] as num).toInt(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

final deviceStorageProvider = FutureProvider<DeviceStorage?>(
  (ref) => DeviceStorage.read(),
);

/// Battery and the OS thermal status, polled while this device serves a
/// model. [thermalStatus] follows Android's PowerManager scale: 0 none,
/// 1 light, 2 moderate, 3 severe, 4 critical, 5 emergency, 6 shutdown;
/// -1 when unknown.
class DevicePower {
  final int level;
  final bool charging;
  final int thermalStatus;
  const DevicePower({
    required this.level,
    required this.charging,
    this.thermalStatus = -1,
  });

  static const thermalLabels = [
    'normal',
    'light',
    'moderate',
    'severe',
    'critical',
    'emergency',
    'shutdown',
  ];

  String get thermalLabel =>
      thermalStatus >= 0 && thermalStatus < thermalLabels.length
      ? thermalLabels[thermalStatus]
      : 'unknown';

  static const _channel = MethodChannel('ondevice_llm/device');

  static Future<DevicePower?> read() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('powerInfo');
      if (m == null) return null;
      return DevicePower(
        level: (m['level'] as num?)?.toInt() ?? -1,
        charging: m['charging'] == true,
        thermalStatus: (m['thermalStatus'] as num?)?.toInt() ?? -1,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> keepScreenOn(bool on) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('keepScreenOn', on);
    } on PlatformException {
      // Not fatal: the server still runs, the screen may sleep.
    } on MissingPluginException {
      // Tests and platforms without the channel.
    }
  }
}
