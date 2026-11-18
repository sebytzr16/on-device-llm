// Signs an engine pack manifest with the maintainer's Ed25519 key, or creates a new
// key file. The private seed never enters the repo: it lives in the file that
// ODLLM_ENGINE_SIGNING_KEY names.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

const _usage =
    'Usage: dart run tool/sign_engine_pack.dart <manifest.json> '
    '<signature.bin>\n'
    '       dart run tool/sign_engine_pack.dart --generate <keyfile>';

Future<void> main(List<String> args) async {
  if (args.length == 2 && args[0] == '--generate') {
    exitCode = await _generate(args[1]);
    return;
  }
  if (args.length != 2) {
    stderr.writeln(_usage);
    exitCode = 64;
    return;
  }
  final keyPath = (Platform.environment['ODLLM_ENGINE_SIGNING_KEY'] ?? '')
      .trim();
  if (keyPath.isEmpty) {
    stderr.writeln(
      'ODLLM_ENGINE_SIGNING_KEY is not set: name the file that holds the '
      'base64 32-byte Ed25519 private seed.',
    );
    exitCode = 2;
    return;
  }
  exitCode = await _sign(keyPath, args[0], args[1]);
}

/// Writes a new random seed and prints the matching public key as base64, so
/// the maintainer can paste it into kEngineSigningPublicKey.
Future<int> _generate(String path) async {
  final file = File(path);
  if (file.existsSync()) {
    stderr.writeln('Refusing to overwrite ${file.path}.');
    return 1;
  }
  final random = Random.secure();
  final seed = List<int>.generate(32, (_) => random.nextInt(256));
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  await file.writeAsString('${base64.encode(seed)}\n');
  stderr.writeln('Keep ${file.path} private: it signs every engine pack.');
  stderr.writeln('Public key for kEngineSigningPublicKey:');
  stdout.writeln(base64.encode(publicKey.bytes));
  return 0;
}

Future<int> _sign(
  String keyPath,
  String manifestPath,
  String signaturePath,
) async {
  final List<int> seed;
  try {
    seed = base64.decode(File(keyPath).readAsStringSync().trim());
  } on FileSystemException catch (e) {
    stderr.writeln('Cannot read the signing key file: ${e.message}');
    return 2;
  } on FormatException {
    stderr.writeln('The signing key file is not base64.');
    return 2;
  }
  if (seed.length != 32) {
    stderr.writeln('The signing key file must hold a 32-byte Ed25519 seed.');
    return 2;
  }
  final List<int> manifest;
  try {
    manifest = File(manifestPath).readAsBytesSync();
  } on FileSystemException catch (e) {
    stderr.writeln('Cannot read $manifestPath: ${e.message}');
    return 2;
  }
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final signature = await Ed25519().sign(manifest, keyPair: keyPair);
  File(signaturePath).writeAsBytesSync(signature.bytes, flush: true);
  stdout.writeln('Signed $manifestPath -> $signaturePath');
  return 0;
}
