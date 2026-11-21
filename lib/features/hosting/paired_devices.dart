import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'pairing_code.dart';

class PairedDevice {
  final String id, name, tokenHash;
  final DateTime pairedAt;
  PairedDevice(this.id, this.name, this.tokenHash, this.pairedAt);
  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'hash': tokenHash,
    'pairedAt': pairedAt.toIso8601String(),
  };
}

/// Only digests are retained. Revocation is persisted before changing live auth.
class PairedDevices {
  static const storageKey = 'host_paired_devices';
  final Future<void> Function(String) save;
  PairedDevices({required this.save});
  final _devices = <PairedDevice>[];
  final _principals = <String, String>{};
  List<PairedDevice> get devices => List.unmodifiable(_devices);
  bool legacyEnabled = true;
  Future<void> _writes = Future.value();

  static Future<PairedDevices> load({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) async {
    final result = PairedDevices(
      save: (raw) => storage.write(key: storageKey, value: raw),
    );
    final raw = await storage.read(key: storageKey);
    if (raw != null) {
      Object? decoded;
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        // A truncated write must not stop hosting from ever starting: the
        // in-app recovery path loads this storage too (audit 06a2-2).
        decoded = null;
      }
      final stored = decoded is Map ? decoded : null;
      // A stored record that cannot establish its state must not re-enable
      // the installation token after it was revoked, so a corrupt record
      // defaults to disabled (the token is kept separately) (audit 06a1-8).
      final legacy = stored?['legacyEnabled'];
      result.legacyEnabled = legacy is bool ? legacy : false;
      final devices = stored?['devices'];
      if (devices is List) {
        for (final entry in devices) {
          final device = _device(entry);
          if (device != null) result._add(device);
        }
      }
    }
    return result;
  }

  /// A stored entry, or null when a field is missing or has another type.
  static PairedDevice? _device(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id'], name = entry['name'];
    final hash = entry['hash'], pairedAt = entry['pairedAt'];
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        hash is! String ||
        pairedAt is! String) {
      return null;
    }
    final at = DateTime.tryParse(pairedAt);
    if (at == null) return null;
    return PairedDevice(id, name, hash, at);
  }

  Future<T> _change<T>(Future<T> Function() action) {
    final next = _writes.catchError((_) {}).then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _persist(List<PairedDevice> devices, bool legacy) => save(
    jsonEncode({
      'legacyEnabled': legacy,
      'devices': [for (final d in devices) d.toJson()],
    }),
  );

  void _add(PairedDevice device) {
    _devices.add(device);
    _principals[device.tokenHash] = device.id;
  }

  Future<String> issue(String name) => _change(() async {
    if (_devices.length >= 100) throw StateError('Paired device limit reached');
    final token = PairingCode.secret();
    final device = PairedDevice(
      PairingCode.secret(),
      name,
      sha256.convert(utf8.encode(token)).toString(),
      DateTime.now(),
    );
    await _persist([..._devices, device], legacyEnabled);
    _add(device);
    return token;
  });

  Future<void> revoke(String id) => _change(() async {
    final next = _devices.where((d) => d.id != id).toList();
    final legacy = id == 'legacy' ? false : legacyEnabled;
    await _persist(next, legacy);
    _devices.clear();
    _principals.clear();
    next.forEach(_add);
    legacyEnabled = legacy;
  });

  /// Called only after the old installation token has been deleted.
  Future<void> allowNewLegacyToken() => _change(() async {
    await _persist(_devices, true);
    legacyEnabled = true;
  });

  String? principal(String token) {
    if (token.length != 44) return null; // Base64url-encoded 32-byte secret.
    final hash = sha256.convert(utf8.encode(token)).toString();
    return _principals[hash];
  }

  static bool sameToken(String provided, String expected) {
    final a = utf8.encode(provided), b = utf8.encode(expected);
    var difference = a.length ^ b.length;
    for (var i = 0; i < b.length; i++) {
      difference |= (i < a.length ? a[i] : 0) ^ b[i];
    }
    return difference == 0;
  }
}
