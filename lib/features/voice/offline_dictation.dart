import 'package:flutter/services.dart';

/// Android-only channel whose native implementation never creates a network
/// recognizer. Session ids discard late events from a cancelled/replaced run.
class OfflineDictation {
  static const channel = MethodChannel('ondevice_llm/offline_dictation');
  static int _nextSession = 0;
  int? _session;
  bool _disposed = false;
  void Function(String, bool)? _onResult;
  void Function(String)? _onError;

  OfflineDictation() {
    channel.setMethodCallHandler(_event);
  }

  Future<void> _event(MethodCall call) async {
    final args = call.arguments;
    if (_disposed ||
        args is! Map ||
        _session == null ||
        args['session'] != _session) {
      return;
    }
    if (call.method == 'result') {
      final text = args['text'];
      if (text is! String) return;
      final isFinal = args['final'] == true;
      if (isFinal) _session = null;
      _onResult?.call(text, isFinal);
    } else if (call.method == 'error') {
      _session = null;
      _onError?.call(args['code'] as String? ?? 'offline_recognition_failed');
    }
  }

  Future<void> listen({
    required void Function(String, bool) onResult,
    required void Function(String) onError,
    String? localeId,
  }) async {
    if (_disposed) throw StateError('Dictation has been disposed.');
    final token = ++_nextSession;
    _session = token;
    _onResult = onResult;
    _onError = onError;
    try {
      await channel.invokeMethod<void>('listen', {
        'session': token,
        'localeId': ?localeId,
      });
    } catch (_) {
      if (_session == token) _session = null;
      rethrow;
    }
  }

  Future<void> stop() => channel.invokeMethod<void>('stop');

  Future<void> cancel() async {
    _session = null;
    await channel.invokeMethod<void>('cancel');
  }

  Future<void> dispose() async {
    _disposed = true;
    _session = null;
    channel.setMethodCallHandler(null);
    try {
      await channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // The channel is absent in widget tests and on non-Android platforms.
    } on PlatformException {
      // The native activity may already be gone.
    }
  }
}
