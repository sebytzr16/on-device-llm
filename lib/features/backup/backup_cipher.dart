import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:collection/collection.dart';

/// Versioned password-encrypted envelope. AES-GCM authenticates the entire
/// archive; each backup gets a fresh salt and nonce.
class BackupCipher {
  static final _magic = ascii.encode('ODLLMBK1');
  static const maxPlainBytes = 96 * 1024 * 1024;
  static const maxEncryptedBytes = maxPlainBytes + 52;
  static const maxFileBytes = 2 * 1024 * 1024 * 1024;
  static final _kdf = Pbkdf2.hmacSha256(iterations: 250000, bits: 256);
  static final _cipher = AesGcm.with256bits();

  /// Same authenticated envelope as byte exports, with bounded memory.
  static Future<void> encryptFile(
    File plain,
    File output,
    String password,
  ) async {
    if (password.length < 12 || await plain.length() > maxFileBytes) {
      throw const FormatException('Invalid password or oversized backup.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final file = await output.open(mode: FileMode.write);
    var success = false;
    try {
      await file.writeFrom([
        ..._magic,
        ...salt,
        ...nonce,
        ...List.filled(16, 0),
      ]);
      Mac? mac;
      await for (final chunk in _cipher.encryptStream(
        plain.openRead(),
        secretKey: key,
        nonce: nonce,
        onMac: (value) => mac = value,
      )) {
        await file.writeFrom(chunk);
      }
      if (mac == null) {
        throw StateError('Backup authentication was not produced.');
      }
      await file.setPosition(36);
      await file.writeFrom(mac!.bytes);
      await file.flush();
      success = true;
    } finally {
      await file.close();
      if (!success && await output.exists()) await output.delete();
    }
  }

  /// Output is private staging data; callers must not read or promote it
  /// until this future completes and the final authentication tag passes.
  static Future<void> decryptFile(
    File encrypted,
    File output,
    String password,
  ) async {
    final length = await encrypted.length();
    if (length < 52 || length > maxFileBytes + 52) {
      throw const FormatException('Invalid or oversized backup file.');
    }
    final input = await encrypted.open();
    final header = await input.read(52);
    await input.close();
    if (header.length != 52 ||
        !const ListEquality().equals(header.sublist(0, 8), _magic)) {
      throw const FormatException('Invalid backup file.');
    }
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: header.sublist(8, 24),
    );
    final file = await output.open(mode: FileMode.write);
    var success = false;
    try {
      await for (final chunk in _cipher.decryptStream(
        encrypted.openRead(52),
        secretKey: key,
        nonce: header.sublist(24, 36),
        mac: Mac(header.sublist(36, 52)),
      )) {
        await file.writeFrom(chunk);
      }
      await file.flush();
      success = true;
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong password or damaged backup.');
    } finally {
      await file.close();
      if (!success && await output.exists()) await output.delete();
    }
  }

  static Future<Uint8List> encrypt(List<int> plain, String password) async {
    if (password.length < 12) {
      throw const FormatException(
        'Use a backup password of at least 12 characters.',
      );
    }
    if (plain.length > maxPlainBytes) {
      throw const FormatException('Backup exceeds the 96 MB safety limit.');
    }
    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => random.nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final box = await _cipher.encrypt(plain, secretKey: key, nonce: nonce);
    return Uint8List.fromList([
      ..._magic,
      ...salt,
      ...nonce,
      ...box.mac.bytes,
      ...box.cipherText,
    ]);
  }

  static Future<Uint8List> decrypt(List<int> encrypted, String password) async {
    if (encrypted.length < 52 ||
        encrypted.length > maxEncryptedBytes ||
        !const ListEquality().equals(encrypted.take(8).toList(), _magic)) {
      throw const FormatException('Invalid or oversized backup file.');
    }
    final salt = encrypted.sublist(8, 24);
    final nonce = encrypted.sublist(24, 36);
    final mac = Mac(encrypted.sublist(36, 52));
    final key = await _kdf.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    try {
      final plain = await _cipher.decrypt(
        SecretBox(encrypted.sublist(52), nonce: nonce, mac: mac),
        secretKey: key,
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException('Wrong password or damaged backup.');
    }
  }
}
