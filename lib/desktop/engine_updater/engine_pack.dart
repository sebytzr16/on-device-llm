import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Owner's Ed25519 public key (base64) compiled into the app; the private key
/// stays with the maintainer, outside the repo. While the placeholder is here every
/// engine pack stays untrusted, so no update is ever offered or installed.
const kEngineSigningPublicKey = 'ue7Sz6hfeSIttHyVHE3rYaaV8R7gSkxCNqhzkbzYaUQ=';

/// Release tags of engine packs: `engine-b<build>` or `engine-b<build>-<rev>`.
final enginePackTag = RegExp(r'^engine-b(\d+)(?:-(\d+))?$');

/// Bare `*.dll` names, the same rule EngineFiles.parse applies to the bundled
/// manifest; `/`, `\`, `:` and `..` never reach a path.
final _engineFileName = RegExp(r'^[^/\\:]+\.dll$', caseSensitive: false);

/// True for a bare pack file name (one `*.dll`, no directories, no `..`).
bool isEnginePackFileName(String name) =>
    _engineFileName.hasMatch(name) && !name.contains('..');

/// Build and revision of an engine release tag; null for any other tag.
({int build, int revision})? enginePackVersion(String? tag) {
  final match = enginePackTag.firstMatch(tag ?? '');
  if (match == null) return null;
  final build = int.tryParse(match.group(1)!);
  final revision = match.group(2) == null ? 0 : int.tryParse(match.group(2)!);
  if (build == null || revision == null) return null;
  return (build: build, revision: revision);
}

/// Orders engine release tags: build number first, then revision. Unparsable
/// tags count as oldest, so they never win against a real pack.
int compareEnginePackVersions(String a, String b) {
  final x = enginePackVersion(a), y = enginePackVersion(b);
  if (x == null || y == null) {
    if (x == null && y == null) return a.compareTo(b);
    return x == null ? -1 : 1;
  }
  if (x.build != y.build) return x.build.compareTo(y.build);
  return x.revision.compareTo(y.revision);
}

/// Strict SemVer, with build metadata excluded from precedence.
({List<int> core, List<String> pre})? _semver(String value) {
  final match = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  ).firstMatch(value);
  if (match == null) return null;
  final core = [for (var i = 1; i <= 3; i++) int.tryParse(match.group(i)!)];
  final pre = match.group(4)?.split('.') ?? <String>[];
  if (core.contains(null) || pre.any((s) => RegExp(r'^0\d+$').hasMatch(s))) {
    return null;
  }
  return (core: core.cast<int>(), pre: pre);
}

int _compareSemver(
  ({List<int> core, List<String> pre}) a,
  ({List<int> core, List<String> pre}) b,
) {
  for (var i = 0; i < 3; i++) {
    final order = a.core[i].compareTo(b.core[i]);
    if (order != 0) return order;
  }
  if (a.pre.isEmpty || b.pre.isEmpty) {
    return a.pre.isEmpty == b.pre.isEmpty ? 0 : (a.pre.isEmpty ? 1 : -1);
  }
  for (var i = 0; i < a.pre.length && i < b.pre.length; i++) {
    final x = a.pre[i], y = b.pre[i];
    final xn = RegExp(r'^\d+$').hasMatch(x);
    final yn = RegExp(r'^\d+$').hasMatch(y);
    final order = xn && yn
        ? (x.length == y.length ? x.compareTo(y) : x.length.compareTo(y.length))
        : xn != yn
        ? (xn ? -1 : 1)
        : x.compareTo(y);
    if (order != 0) return order;
  }
  return a.pre.length.compareTo(b.pre.length);
}

/// One DLL of a pack; [sha256] is checked again after extraction.
class EnginePackFile {
  final String name;
  final int size;
  final String sha256;
  const EnginePackFile(this.name, this.size, this.sha256);
}

/// A signed `engine-pack-windows-x64.json` manifest. Only packs whose
/// signature matches [kEngineSigningPublicKey] are looked at at all.
class EnginePackManifest {
  final String engine;
  final int revision;
  final int bridgeApi;
  final String minApp;
  final int? cudaMajor;
  final List<EnginePackFile> files;
  final String zipSha256;
  const EnginePackManifest({
    required this.engine,
    this.revision = 0,
    required this.bridgeApi,
    required this.minApp,
    required this.files,
    required this.zipSha256,
    this.cudaMajor,
  });

  /// Throws [FormatException] on anything malformed: a partially written or
  /// hostile manifest must never reach the installer.
  factory EnginePackManifest.parse(List<int> bytes) {
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw const FormatException('Engine pack manifest is not UTF-8 JSON.');
    }
    if (decoded is! Map) {
      throw const FormatException('Engine pack manifest is not an object.');
    }
    if (decoded['version'] is! int || decoded['version'] != 1) {
      throw const FormatException('Unsupported engine pack manifest version.');
    }
    final engine = decoded['engine'];
    if (engine is! String || !RegExp(r'^b\d+$').hasMatch(engine)) {
      throw const FormatException('Engine pack manifest has no engine tag.');
    }
    final revision = decoded.containsKey('revision') ? decoded['revision'] : 0;
    if (revision is! int || revision < 0) {
      throw const FormatException(
        'Engine pack manifest has an invalid revision.',
      );
    }
    final bridgeApi = decoded['bridgeApi'];
    if (bridgeApi is! int || bridgeApi < 1) {
      throw const FormatException('Engine pack manifest has no bridge API.');
    }
    final minApp = decoded['minApp'];
    if (minApp is! String || _semver(minApp) == null) {
      throw const FormatException(
        'Engine pack manifest has no minimum app version.',
      );
    }
    final rawCudaMajor = decoded['cudaMajor'];
    int? cudaMajor;
    if (rawCudaMajor != null) {
      if (rawCudaMajor is! int || rawCudaMajor < 1) {
        throw const FormatException(
          'Engine pack manifest has an invalid CUDA version.',
        );
      }
      cudaMajor = rawCudaMajor;
    }
    final rawFiles = decoded['files'];
    if (rawFiles is! List) {
      throw const FormatException('Engine pack manifest has no file list.');
    }
    final zipSha256 = decoded['zipSha256'];
    if (zipSha256 is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(zipSha256)) {
      throw const FormatException('Engine pack manifest has no zip checksum.');
    }
    final names = <String>{};
    final entries = <EnginePackFile>[];
    for (final item in rawFiles) {
      if (item is! Map) {
        throw const FormatException(
          'Engine pack manifest has an invalid file entry.',
        );
      }
      final name = item['name'];
      final size = item['size'];
      final hash = item['sha256'];
      if (name is! String ||
          size is! int ||
          hash is! String ||
          !isEnginePackFileName(name) ||
          size < 0 ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
          !names.add(name.toLowerCase())) {
        throw const FormatException(
          'Engine pack manifest has an invalid file entry.',
        );
      }
      entries.add(EnginePackFile(name, size, hash.toLowerCase()));
    }
    if (entries.isEmpty) {
      throw const FormatException('Engine pack manifest lists no files.');
    }
    return EnginePackManifest(
      engine: engine,
      revision: revision,
      bridgeApi: bridgeApi,
      minApp: minApp,
      cudaMajor: cudaMajor,
      files: List.unmodifiable(entries),
      zipSha256: zipSha256.toLowerCase(),
    );
  }

  /// True when this app can run the pack: the same bridge API and an app at
  /// least as new as [minApp].
  bool compatible({required String appVersion, required int bridgeApi}) {
    if (bridgeApi != this.bridgeApi) return false;
    final app = _semver(appVersion), min = _semver(minApp);
    if (app == null || min == null) return false;
    return _compareSemver(app, min) >= 0;
  }
}

/// True when [signature] is the maintainer's Ed25519 signature over [manifestBytes].
/// A placeholder or unreadable key and any wrong-length or invalid signature
/// are never authentic; the caller treats false as "do not offer this pack".
Future<bool> verifySignature(
  List<int> manifestBytes,
  List<int> signature, {
  String publicKey = kEngineSigningPublicKey,
}) async {
  // The placeholder cannot verify anything: nothing is trusted until the maintainer
  // replaces it with the real public key.
  if (publicKey.isEmpty || publicKey == 'REPLACE_WITH_OWNER_PUBLIC_KEY') {
    return false;
  }
  if (signature.length != 64) return false;
  final SimplePublicKey key;
  try {
    key = SimplePublicKey(base64.decode(publicKey), type: KeyPairType.ed25519);
  } on FormatException {
    return false;
  }
  if (key.bytes.length != 32) return false;
  try {
    return await Ed25519().verify(
      manifestBytes,
      signature: Signature(signature, publicKey: key),
    );
  } catch (_) {
    // Malformed curve points are untrusted input, never a check failure.
    return false;
  }
}
