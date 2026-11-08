import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent host identity. Keep both PEMs together so interrupted writes cannot
/// pair a new certificate with an old private key.
class HostingTls {
  final String certificatePem, privateKeyPem;
  HostingTls(this.certificatePem, this.privateKeyPem);

  String get fingerprint => sha256.convert(_der(certificatePem)).toString();

  SecurityContext get context => SecurityContext(withTrustedRoots: false)
    ..useCertificateChainBytes(utf8.encode(certificatePem))
    ..usePrivateKeyBytes(utf8.encode(privateKeyPem));

  static List<int> _der(String pem) =>
      base64Decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''));

  static Future<HostingTls> load({Directory? directory}) async {
    final dir = directory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final file = File('${dir.path}/hosting-tls.json');
    if (await file.exists()) {
      try {
        final data = jsonDecode(await file.readAsString()) as Map;
        final tls = HostingTls(data['cert'] as String, data['key'] as String);
        final cert = X509Utils.x509CertificateFromPem(tls.certificatePem);
        final now = DateTime.now();
        final validity = cert.tbsCertificate!.validity;
        if (now.isBefore(validity.notBefore) ||
            !now.isBefore(validity.notAfter)) {
          throw const FormatException('Expired TLS identity');
        }
        // Loading into the native context checks key/certificate compatibility.
        tls.context;
        return tls;
      } on FileSystemException {
        rethrow; // Storage failures must never rotate a valid host identity.
      } on Object {
        // Missing, corrupt, expired or mismatched identity: generate once below.
      }
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
        // quarter. Rotation happens only when this identity becomes invalid.
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
    final pending = File('${file.path}.pending');
    await pending.create();
    if (Platform.isLinux || Platform.isMacOS || Platform.isAndroid) {
      final result = await Process.run('chmod', ['600', pending.path]);
      if (result.exitCode != 0) {
        throw FileSystemException('Protect TLS key', pending.path);
      }
    }
    await pending.writeAsString(
      jsonEncode({'cert': tls.certificatePem, 'key': tls.privateKeyPem}),
      flush: true,
    );
    await pending.rename(file.path);
    return tls;
  }
}
