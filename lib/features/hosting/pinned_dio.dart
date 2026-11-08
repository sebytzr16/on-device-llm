import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'tls_pinning.dart';

/// Pool only connections that share both an endpoint and certificate identity.
/// Reused by inference and workspace transports, including their SSE streams.
class PinnedDioClients {
  final _clients = <String, Dio>{};

  Dio forEndpoint(Dio fallback, Uri? endpoint, String? pin) {
    if (pin == null) return fallback;
    if (endpoint == null ||
        endpoint.scheme != 'https' ||
        !validFingerprint(pin)) {
      throw const FormatException('Invalid pinned connection');
    }
    final key = '${endpoint.origin}|$pin';
    return _clients.putIfAbsent(key, () {
      final dio = Dio(fallback.options.copyWith(followRedirects: false));
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () => pinnedHttpClient(endpoint, pin),
        validateCertificate: (cert, host, port) =>
            cert != null &&
            host == endpoint.host &&
            port == endpoint.port &&
            matchesFingerprint(cert, pin),
      );
      return dio;
    });
  }

  void close() {
    for (final client in _clients.values) {
      client.close(force: true);
    }
    _clients.clear();
  }
}

bool isTlsFailure(DioException error) =>
    error.type == DioExceptionType.badCertificate ||
    error.error is HandshakeException;
