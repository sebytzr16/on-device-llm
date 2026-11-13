import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class HostingTlsException implements Exception {
  final Object cause;
  const HostingTlsException(this.cause);
}

/// Persistent host identity. Keep both PEMs together so interrupted writes cannot
/// pair a new certificate with an old private key.
class HostingTls {
  static Future<void> _loads = Future.value();
  final String certificatePem, privateKeyPem;
  HostingTls(this.certificatePem, this.privateKeyPem);

  String get fingerprint => sha256.convert(_der(certificatePem)).toString();

  SecurityContext get context => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

  static List<int> _der(String pem) =>
      base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''));

  static Future<HostingTls> load({
    Directory? directory,
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) async {
    final next = _loads
        .catchError((_) {})
        .then((_) => _load(directory: directory, storage: storage));
    _loads = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    try {
      return await next;
    } catch (error) {
      throw HostingTlsException(error);
    }
  }

  /// Deletes the stored host TLS identity (secure-storage key, fingerprint marker,
  /// JSON and pending files) so the next [load] generates a fresh identity.
  /// Runs inside the same [_loads] serialization chain as [load].
  static Future<void> reset({
    Directory? directory,
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) async {
    final next = _loads.catchError((_) {}).then((_) async {
      final dir = directory ?? await getApplicationSupportDirectory();
      final file = File('${dir.path}/hosting-tls.json');
      final pending = File('${file.path}.pending');
      final marker = File('${dir.path}/hosting-tls.fingerprint');
      final storageKey =
          'hosting_tls.${sha256.convert(utf8.encode(dir.absolute.path))}';
      await storage.delete(key: storageKey);
      if (await marker.exists()) await marker.delete();
      if (await file.exists()) await file.delete();
      if (await pending.exists()) await pending.delete();
    });
    _loads = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    await next;
  }

  static Future<HostingTls> _load({
    Directory? directory,
    required FlutterSecureStorage storage,
  }) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/hosting-tls.json');
    final pending = File('${file.path}.pending');
    final marker = File('${dir.path}/hosting-tls.fingerprint');
    final storageKey =
        'hosting_tls.${sha256.convert(utf8.encode(dir.absolute.path))}';
    // Read errors propagate: never replace an identity because its vault failed.
    final saved = await storage.read(key: storageKey);
    HostingTls decode(String raw) {
      final data = jsonDecode(raw) as Map;
      final tls = HostingTls(data['cert'] as String, data['key'] as String);
      final cert = X509Utils.x509CertificateFromPem(tls.certificatePem);
      final validity = cert.tbsCertificate!.validity;
      final now = DateTime.now();
      if (now.isBefore(validity.notBefore) ||
          !now.isBefore(validity.notAfter)) {
        throw const FormatException(
          'Expired TLS identity; re-pairing required',
        );
      }
      tls.context;
      return tls;
    }

    Future<void> verifyMarker(HostingTls tls) async {
      if (await marker.exists() &&
          await marker.readAsString() != tls.fingerprint) {
        throw StateError('Host identity changed; explicit re-pairing required');
      }
    }

    Future<void> finish(HostingTls tls) async {
      await verifyMarker(tls);
      // Only a public fingerprint reaches disk. Write it before deleting the
      // migration source, so a later lost vault never silently changes the pin.
      await marker.writeAsString(tls.fingerprint, flush: true);
      if (await file.exists()) await file.delete();
      if (await pending.exists()) await pending.delete();
    }

    if (saved != null) {
      final tls = decode(saved);
      await finish(tls);
      return tls;
    }
    if (await file.exists() || await pending.exists()) {
      final source = await file.exists() ? file : pending;
      final raw = await source.readAsString();
      final tls = decode(raw);
      await verifyMarker(tls);
      await storage.write(key: storageKey, value: raw);
      if (await storage.read(key: storageKey) != raw) {
        throw StateError('TLS identity secure-storage verification failed');
      }
      await finish(tls);
      return tls;
    }
    if (await marker.exists()) {
      throw StateError(
        'TLS identity lost; restore secure storage or explicitly '
        'remove the host fingerprint and re-pair all devices',
      );
    }
    final tls = await Isolate.run(() {
      final pair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
      final key = pair.privateKey as RSAPrivateKey;
      final csr = X509Utils.generateRsaCsrPem(
        {'CN': 'OnDevice LLM'},
        key,
        pair.publicKey as RSAPublicKey,
      );
      return HostingTls(
        // Long-lived pinned identity avoids forcing phones to re-pair every
        // quarter. Invalid identities fail closed until explicitly recovered.
        X509Utils.generateSelfSignedCertificate(
          key,
          csr,
          3650,
          cA: false,
          extKeyUsage: [ExtendedKeyUsage.SERVER_AUTH],
        ),
        CryptoUtils.encodeRSAPrivateKeyToPem(key),
      );
    });
    tls.context;
    final raw = jsonEncode({
      'cert': tls.certificatePem,
      'key': tls.privateKeyPem,
    });
    await storage.write(key: storageKey, value: raw);
    if (await storage.read(key: storageKey) != raw) {
      throw StateError('TLS identity secure-storage verification failed');
    }
    await finish(tls);
    return tls;
  }
}
