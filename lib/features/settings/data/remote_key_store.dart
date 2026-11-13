import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists remote API keys and custom header values by profile id, outside
/// the plaintext settings.
abstract class RemoteKeyStore {
  Future<Map<String, String>> readAll();
  Future<void> write(String profileId, String key);
  Future<void> delete(String profileId);
  Future<Map<String, Map<String, String>>> readAllHeaders();
  Future<void> writeHeaders(String profileId, Map<String, String> headers);
  Future<void> deleteHeaders(String profileId);
}

/// Android Keystore-backed storage (AES-GCM, RSA-wrapped key) via
/// flutter_secure_storage. Keys and header values are only ever sent to the
/// server the profile points at.
class SecureRemoteKeyStore implements RemoteKeyStore {
  static const _prefix = 'remote_key.';
  static const _headersPrefix = 'remote_headers.';
  final FlutterSecureStorage _storage;

  SecureRemoteKeyStore({FlutterSecureStorage? storage})
    : _storage =
          storage ?? const FlutterSecureStorage(aOptions: AndroidOptions());

  @override
  Future<Map<String, String>> readAll() async {
    final all = await _storage.readAll();
    return {
      for (final e in all.entries)
        if (e.key.startsWith(_prefix) && e.value.isNotEmpty)
          e.key.substring(_prefix.length): e.value,
    };
  }

  @override
  Future<void> write(String profileId, String key) =>
      _storage.write(key: '$_prefix$profileId', value: key);

  @override
  Future<void> delete(String profileId) =>
      _storage.delete(key: '$_prefix$profileId');

  @override
  Future<Map<String, Map<String, String>>> readAllHeaders() async {
    final all = await _storage.readAll();
    final out = <String, Map<String, String>>{};
    for (final e in all.entries) {
      if (!e.key.startsWith(_headersPrefix)) continue;
      try {
        final decoded = jsonDecode(e.value);
        if (decoded is! Map) continue;
        final headers = <String, String>{
          for (final h in decoded.entries)
            if (h.key is String && h.value is String)
              h.key as String: h.value as String,
        };
        if (headers.isNotEmpty) {
          out[e.key.substring(_headersPrefix.length)] = headers;
        }
      } on FormatException {
        // One damaged entry must not hide the other connections' values.
        continue;
      }
    }
    return out;
  }

  @override
  Future<void> writeHeaders(String profileId, Map<String, String> headers) {
    if (headers.isEmpty) return deleteHeaders(profileId);
    return _storage.write(
      key: '$_headersPrefix$profileId',
      value: jsonEncode(headers),
    );
  }

  @override
  Future<void> deleteHeaders(String profileId) =>
      _storage.delete(key: '$_headersPrefix$profileId');
}
