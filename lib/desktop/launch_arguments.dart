import 'dart:async';

import 'package:flutter/services.dart';
import 'package:logging/logging.dart';

/// Both cold launches and WM_COPYDATA use this serialized import queue.
class DesktopLaunchArguments {
  static const channel = MethodChannel('ondevice_llm/desktop');
  final Future<void> Function(String) openModel;
  final VoidCallback? onRefreshRateChanged;
  Future<void> _pending = Future.value();
  bool _disposed = false;

  DesktopLaunchArguments(this.openModel, {this.onRefreshRateChanged});

  Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'launchArgs') await accept(call.arguments);
      if (call.method == 'refreshRateChanged') onRefreshRateChanged?.call();
    });
    try {
      await accept(await channel.invokeMethod<Object?>('getInitialArgs'));
    } on MissingPluginException {
      // Widget tests and non-Windows previews have no native runner.
    }
  }

  Future<void> accept(Object? arguments) {
    if (arguments is! List) return _pending;
    final paths = arguments.whereType<String>().where(
      (path) => path.toLowerCase().endsWith('.gguf'),
    );
    for (final path in paths) {
      _pending = _pending.then((_) async {
        if (_disposed) return;
        Logger('desktop.launch').info('GGUF launch argument received');
        try {
          await openModel(path);
        } catch (error, stack) {
          Logger('desktop.launch').warning('GGUF import failed', error, stack);
        }
      });
    }
    return _pending;
  }

  void dispose() {
    _disposed = true;
    channel.setMethodCallHandler(null);
  }
}
