import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'tls_pinning.dart';

/// Why trading a pairing code for the access token failed.
enum PairingFailure { wrongCode, lockedOut, expired, unreachable }

class PairingException implements Exception {
  final PairingFailure failure;
  const PairingException(this.failure);
  @override
  String toString() => 'PairingException($failure)';
}

/// Six digits shown next to a running server. A device that found the
/// server nearby sends them once to receive the access token, so nobody
/// has to type the token itself.
abstract final class PairingCode {
  static const length = 6;

  /// Wrong codes the server accepts before typed pairing locks until expiry:
  /// guessing one code in a million five times is not a way in.
  static const maxFailures = 5;

  static String secret() {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256)));
  }

  static Future<String> redeemQr(
    PairingQr qr, {
    Duration timeout = const Duration(seconds: 8),
  }) => redeem(
    qr.endpoint,
    '',
    timeout: timeout,
    qr: qr,
    fingerprint: qr.fingerprint,
  );

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(length, (_) => r.nextInt(10)).join();
  }

  /// Digits only, so "123 456" and "123-456" both work.
  static String normalize(String text) => text.replaceAll(RegExp(r'\D'), '');

  /// Typed-code bootstrap: public metadata carries no secrets. As in Phase A,
  /// discovery is unauthenticated; the UI requires a trusted network. QR pins
  /// are delivered out of band and never use this endpoint.
  static Future<(String, String)> tlsTarget(String endpoint) async {
    final uri = Uri.parse(endpoint);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri.resolve('pairing-tls'))
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) throw const FormatException();
      final body =
          jsonDecode(
                await response
                    .transform(utf8.decoder)
                    .join()
                    .timeout(const Duration(seconds: 8)),
              )
              as Map;
      final port = body['port'];
      final pin = body['fingerprint'];
      if (port is! int ||
          port < 1 ||
          port > 65535 ||
          pin is! String ||
          !validFingerprint(pin)) {
        throw const FormatException();
      }
      return (uri.replace(scheme: 'https', port: port).toString(), pin);
    } catch (_) {
      throw const PairingException(PairingFailure.unreachable);
    } finally {
      client.close(force: true);
    }
  }

  /// The saved connection JSON returned by the server at
  /// [endpoint] (".../v1/") for [code].
  static Future<String> redeem(
    String endpoint,
    String code, {
    Duration timeout = const Duration(seconds: 8),
    PairingQr? qr,
    String? fingerprint,
  }) async {
    final uri = Uri.parse(endpoint);
    // A pin needs HTTPS, and HTTPS needs a valid pin (audit M-02).
    if ((uri.scheme == 'https' || fingerprint != null) &&
        (uri.scheme != 'https' || !validFingerprint(fingerprint))) {
      throw const PairingException(PairingFailure.unreachable);
    }
    final client =
        (fingerprint == null
              ? HttpClient()
              : pinnedHttpClient(uri, fingerprint))
          ..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint).resolve('pair'))
          .timeout(timeout);
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      if (qr != null) request.headers.set('X-Pairing-Mode', 'qr');
      request.write(
        jsonEncode(
          qr == null
              ? {'code': normalize(code)}
              : {'secret': qr.secret, 'hostId': qr.hostId},
        ),
      );
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      switch (response.statusCode) {
        case HttpStatus.ok:
          final body = jsonDecode(text);
          if (body is! Map ||
              body['key'] is! String ||
              (qr != null && body['hostId'] != qr.hostId)) {
            throw const PairingException(PairingFailure.unreachable);
          }
          return jsonEncode({
            'ondevice_llm': 'connection',
            'url': endpoint,
            'model': body['model'] ?? '',
            'key': body['key'],
            'fingerprint': ?fingerprint,
          });
        case HttpStatus.gone:
          throw const PairingException(PairingFailure.expired);
        case HttpStatus.unauthorized:
          throw const PairingException(PairingFailure.wrongCode);
        case HttpStatus.tooManyRequests:
          throw const PairingException(PairingFailure.lockedOut);
        default:
          throw const PairingException(PairingFailure.unreachable);
      }
    } on PairingException {
      rethrow;
    } catch (_) {
      throw const PairingException(PairingFailure.unreachable);
    } finally {
      client.close(force: true);
    }
  }
}

/// One short-lived pairing window. Reservations bound concurrent guesses.
class PairingSession {
  final DateTime expiresAt;
  final DateTime Function() now;
  int _failures;
  int get failures => _failures;
  bool _used = false;
  PairingSession({
    int failures = 0,
    DateTime Function()? now,
    Duration lifetime = const Duration(minutes: 10),
  }) // The counter remains private; rotations may carry its previous budget.
    // ignore: prefer_initializing_formals
    : _failures = failures,
       now = now ?? DateTime.now,
       expiresAt = (now ?? DateTime.now)().add(lifetime);

  bool get expired => !now().isBefore(expiresAt);
  bool get locked => _failures >= PairingCode.maxFailures;
  bool get available => !_used && !expired && !locked;
  bool reserve() {
    if (!available) return false;
    _failures++;
    return true;
  }

  bool accept({bool reserved = true}) {
    if (_used || expired) return false;
    _used = true;
    if (reserved) _failures--;
    return true;
  }
}

/// A QR bootstrap is self-contained; discovery never supplies its identity or URL.
class PairingQr {
  final String endpoint, hostId, secret;
  final String? fingerprint;
  const PairingQr(this.endpoint, this.hostId, this.secret, {this.fingerprint});

  String encode() => jsonEncode({
    'ondevice_llm': 'pairing',
    'url': endpoint,
    'hostId': hostId,
    'secret': secret,
    if (fingerprint != null) 'fingerprint': fingerprint,
  });

  static PairingQr? parse(String text) {
    try {
      final body = jsonDecode(text);
      if (body is! Map ||
          body['ondevice_llm'] != 'pairing' ||
          body['url'] is! String ||
          body['hostId'] is! String ||
          body['secret'] is! String) {
        return null;
      }
      final uri = Uri.parse(body['url'] as String);
      if (!['http', 'https'].contains(uri.scheme) ||
          (uri.scheme == 'https' &&
              !validFingerprint(body['fingerprint'] as String?)) ||
          (uri.scheme == 'http' && body['fingerprint'] != null) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.path != '/v1/' ||
          uri.hasQuery ||
          uri.hasFragment ||
          (body['hostId'] as String).isEmpty ||
          !RegExp(r'^[A-Za-z0-9_-]{43}=$').hasMatch(body['secret'] as String)) {
        return null;
      }
      return PairingQr(
        uri.toString(),
        body['hostId'] as String,
        body['secret'] as String,
        fingerprint: body['fingerprint'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
