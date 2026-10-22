import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists remote API keys by profile id, outside the plaintext settings.
abstract class RemoteKeyStore {
  Future<Map<String, String>> readAll();
  Future<void> write(String profileId, String key);
  Future<void> delete(String profileId);
}

/// Android Keystore-backed storage (AES-GCM, RSA-wrapped key) via
/// flutter_secure_storage. Keys are only ever sent to the server the
/// profile points at.
class SecureRemoteKeyStore implements RemoteKeyStore {
  static const _prefix = 'remote_key.';
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
}
