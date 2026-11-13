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
      final data = jsonDecode(raw) as Map;
      result.legacyEnabled = data['legacyEnabled'] as bool;
      for (final d in data['devices'] as List) {
        result._devices.add(
          PairedDevice(
            d['id'] as String,
            d['name'] as String,
            d['hash'] as String,
            DateTime.parse(d['pairedAt'] as String),
          ),
        );
      }
    }
    return result;
  }

  Future<T> _change<T>(Future<T> Function() action) {
    final next = _writes.catchError((_) {}).then((_) => action());
    _writes = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> _persist(List<PairedDevice> devices, bool legacy) => save(
    jsonEncode({
      'legacyEnabled': legacy,
      'devices': [for (final d in devices) d.toJson()],
    }),
  );

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
    _devices.add(device);
    return token;
  });

  Future<void> revoke(String id) => _change(() async {
    final next = _devices.where((d) => d.id != id).toList();
    final legacy = id == 'legacy' ? false : legacyEnabled;
    await _persist(next, legacy);
    _devices
      ..clear()
      ..addAll(next);
    legacyEnabled = legacy;
  });

  /// Called only after the old installation token has been deleted.
  Future<void> allowNewLegacyToken() => _change(() async {
    await _persist(_devices, true);
    legacyEnabled = true;
  });

  String? principal(String token) {
    final hash = sha256.convert(utf8.encode(token)).toString();
    String? found;
    for (final d in _devices) {
      if (sameToken(hash, d.tokenHash)) found = d.id;
    }
    return found;
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
