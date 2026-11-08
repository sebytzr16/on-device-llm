import 'dart:io';
import 'package:crypto/crypto.dart';

bool validFingerprint(String? value) =>
    value != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(value);

bool matchesFingerprint(X509Certificate cert, String pin) =>
    validFingerprint(pin) && sha256.convert(cert.der).toString() == pin;

/// No platform roots: even a CA-trusted replacement must match this profile.
HttpClient pinnedHttpClient(Uri endpoint, String pin) {
  if (endpoint.scheme != 'https' || !validFingerprint(pin)) {
    throw const FormatException('A certificate pin requires HTTPS');
  }
  return HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..badCertificateCallback = (cert, host, port) =>
        host == endpoint.host &&
        port == endpoint.port &&
        matchesFingerprint(cert, pin);
}
