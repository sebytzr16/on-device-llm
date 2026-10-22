import 'dart:io';

import 'package:flutter/services.dart';

/// Android owns the network transfer; Dart alone verifies and promotes GGUFs.
/// No Flutter engine or loaded model is kept alive for a download.
abstract class SystemDownloads {
  static SystemDownloads? get platform =>
      Platform.isAndroid ? const AndroidSystemDownloads() : null;

  Future<void> enqueue({
    required String id,
    required String url,
    required String fileName,
    required String sha256,
    required int size,
  });
  Future<({String status, int received, String? error})> query(String id);
  Future<void> stage(String id);
  Future<void> cancel(String id);
}

class AndroidSystemDownloads implements SystemDownloads {
  const AndroidSystemDownloads();
  static const channel = MethodChannel('ondevice_llm/downloads');

  @override
  Future<void> enqueue({
    required String id,
    required String url,
    required String fileName,
    required String sha256,
    required int size,
  }) => channel.invokeMethod<void>('enqueue', {
    'id': id,
    'url': url,
    'fileName': fileName,
    'sha256': sha256,
    'size': size,
  });

  @override
  Future<({String status, int received, String? error})> query(
    String id,
  ) async {
    final result = await channel.invokeMapMethod<String, dynamic>('query', {
      'id': id,
    });
    if (result == null) {
      throw StateError('Download service returned no status.');
    }
    return (
      status: result['status'] as String? ?? 'failed',
      received: (result['received'] as num?)?.toInt() ?? 0,
      error: result['error'] as String?,
    );
  }

  @override
  Future<void> stage(String id) =>
      channel.invokeMethod<void>('stage', {'id': id});

  @override
  Future<void> cancel(String id) =>
      channel.invokeMethod<void>('cancel', {'id': id});
}
