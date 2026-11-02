import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Why trading a pairing code for the access token failed.
enum PairingFailure { wrongCode, lockedOut, unreachable }

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

  /// Wrong codes the server accepts before it stops pairing until restart:
  /// guessing one code in a million five times is not a way in.
  static const maxFailures = 5;

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(length, (_) => r.nextInt(10)).join();
  }

  /// Digits only, so "123 456" and "123-456" both work.
  static String normalize(String text) => text.replaceAll(RegExp(r'\D'), '');

  /// The pairing JSON (the same text the QR code holds) from the server at
  /// [endpoint] (".../v1/") for [code].
  static Future<String> redeem(
    String endpoint,
    String code, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final request = await client
          .postUrl(Uri.parse(endpoint).resolve('pair'))
          .timeout(timeout);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'code': normalize(code)}));
      final response = await request.close().timeout(timeout);
      final text = await response
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      switch (response.statusCode) {
        case HttpStatus.ok:
          final body = jsonDecode(text);
          if (body is! Map || body['key'] is! String) {
            throw const PairingException(PairingFailure.unreachable);
          }
          return jsonEncode({
            'ondevice_llm': 'connection',
            'url': endpoint,
            'model': body['model'] ?? '',
            'key': body['key'],
          });
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
  int _failures = 0;
  bool _used = false;
  PairingSession({
    DateTime Function()? now,
    Duration lifetime = const Duration(minutes: 10),
  }) : now = now ?? DateTime.now,
       expiresAt = (now ?? DateTime.now)().add(lifetime);

  bool get expired => !now().isBefore(expiresAt);
  bool get locked => _failures >= PairingCode.maxFailures;
  bool get available => !_used && !expired && !locked;
  bool reserve() {
    if (!available) return false;
    _failures++;
    return true;
  }

  bool accept() {
    if (_used || expired) return false;
    _used = true;
    _failures--;
    return true;
  }
}
