import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/platform/build_identity.dart';
import '../../core/platform/engine_versions.dart';
import '../../inference/ffi/llama_bindings.dart';
import 'engine_pack.dart';

/// The only host the updater talks to: this project's GitHub releases.
const _releasesUrl =
    'https://api.github.com/repos/sebytzr16/on-device-llm/releases?per_page=30';

/// Every release asset must live under this prefix; no other URL is fetched.
const _assetPrefix =
    'https://github.com/sebytzr16/on-device-llm/releases/download/';

/// GitHub redirects release downloads here, and only from an asset URL.
const _assetHostSuffix = '.githubusercontent.com';

const _manifestAsset = 'engine-pack-windows-x64.json';
const _signatureAsset = 'engine-pack-windows-x64.json.sig';
const _zipAsset = 'engine-pack-windows-x64.zip';

/// The plan allows one automatic check a day per installation.
const _checkInterval = Duration(hours: 24);

/// Two loads that never finished mean the pack is broken.
const _crashLimit = 2;

/// One HTTP transaction. [location] replaces [body] for a redirect the caller
/// must vet before following it.
class EngineHttpResponse {
  final int statusCode;
  final String? location;
  final Stream<List<int>> body;
  const EngineHttpResponse(
    this.statusCode, {
    this.location,
    this.body = const Stream<List<int>>.empty(),
  });
}

enum EngineCheckState { upToDate, available, offline, error }

/// What one check found: nothing new, a verified pack with its download size,
/// no network, or a concrete failure to show.
class EngineCheckResult {
  final EngineCheckState state;
  final String? tag;
  final int? size;
  final String? message;
  final DateTime? lastCheck;
  const EngineCheckResult(
    this.state, {
    this.tag,
    this.size,
    this.message,
    this.lastCheck,
  });
}

enum EngineDownloadState { done, cancelled, error }

class EngineDownloadResult {
  final EngineDownloadState state;
  final String? message;
  const EngineDownloadResult(this.state, {this.message});
}

/// Checks GitHub for engine packs, verifies and stages them, and writes the
/// marker that makes the loader open a pack instead of the bundled DLLs.
/// Fetch, clock, root and the smoke test are injected so tests are offline.
class EngineUpdater {
  final Future<EngineHttpResponse> Function(Uri uri, {String? range}) fetch;
  final Future<bool> Function(String path) openSmoke;
  final DateTime Function() clock;
  final String appVersion;
  final int bridgeApi;
  final String signingPublicKey;

  /// Engines root; the default is `<application support dir>/engines`.
  final Directory? root;

  String? _rootDir;
  EnginePackFiles? _files;
  _PendingPack? _pending;
  _PendingPack? _ready;

  EngineUpdater({
    Future<EngineHttpResponse> Function(Uri uri, {String? range})? fetch,
    Future<bool> Function(String path)? openSmoke,
    DateTime Function()? clock,
    String? appVersion,
    this.bridgeApi = kEngineBridgeApi,
    this.signingPublicKey = kEngineSigningPublicKey,
    this.root,
  }) : fetch = fetch ?? _dioFetch,
       openSmoke = openSmoke ?? enginePackSmoke,
       clock = clock ?? DateTime.now,
       appVersion = appVersion ?? BuildIdentity.version;

  /// Resolves the engines folder and installs the loader hooks; call it at
  /// startup so the first model load can already use a downloaded pack.
  Future<void> prepare() async {
    await _rootPath();
  }

  /// Checks for a newer verified pack at most once a day unless [force].
  Future<EngineCheckResult> check({bool force = false}) async {
    final root = await _rootPath();
    final state = _readState(root);
    final last = state.lastCheck;
    final now = clock();
    if (!force && last != null && now.difference(last) < _checkInterval) {
      return EngineCheckResult(EngineCheckState.upToDate, lastCheck: last);
    }
    _pending = null;
    // Failed checks also count, avoiding repeated automatic network attempts.
    _writeState(root, state.copyWith(lastCheck: now));
    final List<int> body;
    try {
      body = await _body(await fetch(Uri.parse(_releasesUrl)));
    } on _HttpFailure catch (e) {
      return EngineCheckResult(
        EngineCheckState.error,
        message: e.message,
        lastCheck: now,
      );
    } catch (e) {
      return EngineCheckResult(
        EngineCheckState.offline,
        message: '$e',
        lastCheck: now,
      );
    }
    final Object? releases;
    try {
      releases = jsonDecode(utf8.decode(body));
    } on FormatException catch (e) {
      return EngineCheckResult(
        EngineCheckState.error,
        message: 'The release list could not be read: ${e.message}',
        lastCheck: now,
      );
    }
    if (releases is! List) {
      return EngineCheckResult(
        EngineCheckState.error,
        message: 'The release list was not a list.',
        lastCheck: now,
      );
    }
    final candidates = <({String tag, Map<dynamic, dynamic> release})>[];
    for (final item in releases) {
      if (item is! Map) continue;
      final tag = item['tag_name'];
      if (tag is! String || enginePackVersion(tag) == null) continue;
      candidates.add((tag: tag, release: item));
    }
    // Newest build first; the first candidate that verifies and fits wins.
    candidates.sort((a, b) => compareEnginePackVersions(b.tag, a.tag));

    final activeTag = _activeTag(root);
    final bundled = llamaBuildNumber(EnginePins.llamaCppTag) ?? 0;
    for (final candidate in candidates) {
      final tag = candidate.tag;
      if (state.badTags.contains(tag)) continue;
      final version = enginePackVersion(tag)!;
      if (compareEnginePackVersions(tag, 'engine-b$bundled') <= 0) continue;
      if (activeTag != null && compareEnginePackVersions(tag, activeTag) <= 0) {
        continue;
      }
      final assets = _assets(candidate.release);
      if (assets == null) continue;
      final List<int> manifestBytes;
      final List<int> signature;
      try {
        manifestBytes = await _getAsset(assets.manifest);
        signature = await _getAsset(assets.signature);
      } on _HttpFailure catch (e) {
        return EngineCheckResult(
          EngineCheckState.error,
          message: e.message,
          lastCheck: now,
        );
      } catch (e) {
        return EngineCheckResult(
          EngineCheckState.offline,
          message: '$e',
          lastCheck: now,
        );
      }
      if (!await verifySignature(
        manifestBytes,
        signature,
        publicKey: signingPublicKey,
      )) {
        continue;
      }
      final EnginePackManifest manifest;
      try {
        manifest = EnginePackManifest.parse(manifestBytes);
      } on FormatException {
        continue;
      }
      if (manifest.engine != 'b${version.build}' ||
          manifest.revision != version.revision ||
          !manifest.compatible(appVersion: appVersion, bridgeApi: bridgeApi)) {
        continue;
      }
      _pending = _PendingPack(
        tag: tag,
        manifest: manifest,
        zipUrl: assets.zip,
        zipSize: assets.size,
      );
      return EngineCheckResult(
        EngineCheckState.available,
        tag: tag,
        size: assets.size,
        lastCheck: now,
      );
    }
    _pending = null;
    return EngineCheckResult(EngineCheckState.upToDate, lastCheck: now);
  }

  /// Downloads, verifies, extracts and smoke tests the pack found by [check].
  /// A partial file resumes with a Range request; any mismatch deletes the
  /// staging folder, so a damaged pack can never be activated.
  Future<EngineDownloadResult> download({
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final pending = _pending;
    if (pending == null) {
      return const EngineDownloadResult(
        EngineDownloadState.error,
        message: 'No engine update is available.',
      );
    }
    _ready = null;
    final root = await _rootPath();
    final staging = Directory(p.join(root, 'staging', pending.tag));
    final part = File(p.join(staging.path, 'pack.zip.part'));
    final zip = File(p.join(staging.path, 'pack.zip'));
    try {
      await staging.create(recursive: true);
      final existing = await part.exists() ? await part.length() : 0;
      final response = await _openDownload(pending.zipUrl, existing);
      final append = response.statusCode == 206 && existing > 0;
      final sink = part.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      var received = append ? existing : 0;
      var cancelled = false;
      try {
        await for (final chunk in response.body) {
          if (cancelToken?.isCancelled ?? false) {
            cancelled = true;
            break;
          }
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, pending.zipSize);
        }
      } finally {
        await sink.close();
      }
      if (cancelled) {
        // The partial file stays for the next attempt's Range request.
        return const EngineDownloadResult(EngineDownloadState.cancelled);
      }
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != pending.manifest.zipSha256) {
        await _delete(staging);
        return const EngineDownloadResult(
          EngineDownloadState.error,
          message: 'The engine pack zip did not match its signed checksum.',
        );
      }
      if (await zip.exists()) await zip.delete();
      await part.rename(zip.path);
      String? problem;
      try {
        problem = await _extract(zip, staging, pending.manifest);
      } catch (e) {
        // An unreadable archive is a failed install, never a usable pack.
        problem = 'The engine pack archive could not be read: $e';
      }
      if (problem != null) {
        await _delete(staging);
        return EngineDownloadResult(
          EngineDownloadState.error,
          message: problem,
        );
      }
      if (await zip.exists()) await zip.delete();
      // Persist before native code runs: a process crash cannot report back.
      _addBadTag(root, pending.tag);
      final cpuFiles = pending.manifest.files
          .where((file) => LlamaBindings.windowsCpuOf(file.name) != null)
          .toList();
      if (cpuFiles.isEmpty) {
        await _delete(staging);
        return const EngineDownloadResult(
          EngineDownloadState.error,
          message: 'The engine pack has no CPU bridge.',
        );
      }
      for (final file in cpuFiles) {
        var healthy = false;
        try {
          healthy = await openSmoke(p.join(staging.path, file.name));
        } catch (_) {
          // A bridge that crashes or throws on open is what the smoke test
          // exists to catch, so it counts as a failure.
          healthy = false;
        }
        if (healthy) continue;
        await _delete(staging);
        _addBadTag(root, pending.tag);
        return const EngineDownloadResult(
          EngineDownloadState.error,
          message: 'The engine pack failed its smoke test.',
        );
      }
      final state = _readState(root);
      _writeState(
        root,
        state.copyWith(
          badTags: state.badTags.where((tag) => tag != pending.tag).toList(),
        ),
      );
      // GPU runtimes are optional. CPU validation is complete, so a GPU
      // probe must not blacklist an otherwise usable pack.
      pending.unavailableFiles.clear();
      for (final file in pending.manifest.files) {
        if (cpuFiles.contains(file)) continue;
        var healthy = false;
        try {
          healthy = await openSmoke(p.join(staging.path, file.name));
        } catch (_) {}
        if (!healthy) pending.unavailableFiles.add(file.name.toLowerCase());
      }
      _ready = pending;
      return const EngineDownloadResult(EngineDownloadState.done);
    } on _HttpFailure catch (e) {
      await _delete(staging);
      return EngineDownloadResult(
        EngineDownloadState.error,
        message: e.message,
      );
    } catch (e) {
      return EngineDownloadResult(
        EngineDownloadState.error,
        message: 'The engine pack download failed: $e',
      );
    }
  }

  /// Promotes the verified staging pack; the change applies on the next model
  /// load. Returns false when no downloaded pack is waiting.
  Future<bool> activate({String? tag}) async {
    final root = await _rootPath();
    final ready = _ready;
    final wanted = tag ?? ready?.tag;
    if (ready == null || wanted == null || wanted != ready.tag) return false;
    final staging = Directory(p.join(root, 'staging', wanted));
    if (!await staging.exists()) return false;
    // Recheck the exact staged set immediately before promotion.
    final expected = {for (final f in ready.manifest.files) f.name};
    final entries = await staging.list(followLinks: false).toList();
    if (entries.length != expected.length) {
      await _delete(staging);
      _ready = null;
      return false;
    }
    for (final entry in entries) {
      if (entry is! File || !expected.contains(p.basename(entry.path))) {
        await _delete(staging);
        _ready = null;
        return false;
      }
      final file = ready.manifest.files.firstWhere(
        (f) => f.name == p.basename(entry.path),
      );
      if (await entry.length() != file.size ||
          (await sha256.bind(entry.openRead()).first).toString() !=
              file.sha256) {
        await _delete(staging);
        _ready = null;
        return false;
      }
    }
    final target = Directory(p.join(root, wanted));
    // Removed earlier in this run: the old copy may still be mapped. Replace
    // it when it can be deleted now; otherwise wait for the next start.
    final scheduled = File(p.join(root, '$wanted.delete-on-start'));
    try {
      if (await target.exists()) await target.delete(recursive: true);
      if (await scheduled.exists()) await scheduled.delete();
    } on FileSystemException {
      return false;
    }
    await staging.rename(target.path);
    await _writeActive(
      root,
      wanted,
      target.path,
      ready.manifest.cudaMajor,
      ready.unavailableFiles.toList(),
    );
    await _prune(root, wanted);
    _writeState(
      root,
      _readState(root).copyWith(crashCount: 0, revertAcknowledged: false),
    );
    _pending = null;
    _ready = null;
    return true;
  }

  /// Reverts to the bundled engine and clears the crash markers.
  Future<void> useBundled() async {
    _ready = null;
    final root = await _rootPath();
    final active = File(p.join(root, 'active.json'));
    if (await active.exists()) await active.delete();
    _writeState(
      root,
      _readState(root).copyWith(crashCount: 0, revertAcknowledged: false),
    );
  }

  /// Switches to bundled immediately and defers deletion until next startup.
  /// DLLs from these folders may still be mapped by this process.
  Future<void> removeAll() async {
    _pending = null;
    _ready = null;
    final root = await _rootPath();
    await useBundled();
    final directory = Directory(root);
    if (!await directory.exists()) return;
    for (final entity in await directory.list(followLinks: false).toList()) {
      final name = p.basename(entity.path);
      if (entity is! Directory ||
          (enginePackVersion(name) == null && name != 'staging')) {
        continue;
      }
      await File(
        p.join(root, '$name.delete-on-start'),
      ).writeAsString('', flush: true);
    }
  }

  /// The loader's active pack folder, or null for the bundled engine.
  String? activePackDir() => _files?.activePackDir();

  /// Written before a load from the pack and cleared after it succeeded.
  void markLoadStarted() => _files?.markLoadStarted();
  void markLoadSucceeded() => _files?.markLoadSucceeded();

  /// When the last check ran (automatic or forced), for Settings.
  DateTime? get lastCheck {
    final root = _rootDir;
    return root == null ? null : _readState(root).lastCheck;
  }

  /// True after two unfinished loads from the pack, until the user
  /// acknowledges the revert to the bundled engine.
  bool get revertedNotice {
    final root = _rootDir;
    if (root == null) return false;
    final state = _readState(root);
    return state.crashCount >= _crashLimit && !state.revertAcknowledged;
  }

  void acknowledgeRevert() {
    final root = _rootDir;
    if (root == null) return;
    _writeState(root, _readState(root).copyWith(revertAcknowledged: true));
  }

  /// Rebuilds the loader hooks in the model-load isolate, which only receives
  /// the engines root as a plain path.
  static void installIsolateLoader(String rootPath) {
    LlamaBindings.enginePack = EnginePackFiles(
      p.normalize(p.absolute(rootPath)),
    );
  }

  Future<String> _rootPath() async {
    final cached = _rootDir;
    if (cached != null) return cached;
    final directory =
        root ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'engines'),
        );
    final path = p.normalize(p.absolute(directory.path));
    await _deleteScheduledPacks(path);
    _rootDir = path;
    _files ??= EnginePackFiles(path);
    for (final tag in _readState(path).badTags) {
      if (enginePackVersion(tag) != null) {
        await _delete(Directory(p.join(path, 'staging', tag)));
      }
    }
    // The loader runs in this isolate too (probing, estimates), so it must see
    // the same pack as the settings page.
    LlamaBindings.enginePack = _files;
    return path;
  }

  /// The three asset URLs of a release; null when one is missing or is not
  /// under this project's release download prefix, so it is never fetched.
  ({String manifest, String signature, String zip, int size})? _assets(
    Map<dynamic, dynamic> release,
  ) {
    final byName = <String, Map<dynamic, dynamic>>{};
    final assets = release['assets'];
    if (assets is! List) return null;
    for (final asset in assets) {
      if (asset is! Map) continue;
      final name = asset['name'];
      if (name is String) byName[name] = asset;
    }
    String? url(String name) {
      final value = byName[name]?['browser_download_url'];
      return value is String ? value : null;
    }

    final manifest = url(_manifestAsset);
    final signature = url(_signatureAsset);
    final zip = url(_zipAsset);
    if (manifest == null || signature == null || zip == null) return null;
    for (final value in [manifest, signature, zip]) {
      if (!value.startsWith(_assetPrefix)) return null;
    }
    final size = byName[_zipAsset]?['size'];
    return (
      manifest: manifest,
      signature: signature,
      zip: zip,
      size: size is int ? size : 0,
    );
  }

  /// Reads a small asset, following GitHub's own redirect to its asset host.
  Future<List<int>> _getAsset(String url) async {
    if (!url.startsWith(_assetPrefix)) {
      throw _HttpFailure('Refusing a non-GitHub engine pack URL: $url');
    }
    var response = await fetch(Uri.parse(url));
    if (_isRedirect(response.statusCode)) {
      response = await fetch(_redirectTarget(response.location));
    }
    return _body(response);
  }

  /// Opens the zip for reading, resuming after [existing] bytes when the
  /// server honours the Range request.
  Future<EngineHttpResponse> _openDownload(String url, int existing) async {
    if (!url.startsWith(_assetPrefix)) {
      throw _HttpFailure('Refusing a non-GitHub engine pack URL: $url');
    }
    final range = existing > 0 ? '$existing' : null;
    var response = await fetch(Uri.parse(url), range: range);
    if (_isRedirect(response.statusCode)) {
      response = await fetch(_redirectTarget(response.location), range: range);
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw _HttpFailure(
        'GitHub answered ${response.statusCode} for the engine pack.',
      );
    }
    return response;
  }

  /// GitHub serves release downloads from its asset host; nothing else may be
  /// reached, so a redirect is checked before it is requested.
  Uri _redirectTarget(String? location) {
    final target = location == null ? null : Uri.tryParse(location);
    if (target == null ||
        target.scheme != 'https' ||
        !target.host.endsWith(_assetHostSuffix) ||
        target.userInfo.isNotEmpty ||
        target.port != 443) {
      throw _HttpFailure('Refusing an engine pack redirect: $location');
    }
    return target;
  }

  Future<List<int>> _body(EngineHttpResponse response) async {
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw _HttpFailure('GitHub answered ${response.statusCode}.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.body) {
      if (bytes.length + chunk.length > 4 * 1024 * 1024) {
        throw const _HttpFailure('Engine release metadata is too large.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  bool _isRedirect(int status) => status >= 300 && status < 400;

  void _addBadTag(String root, String tag) {
    final state = _readState(root);
    if (state.badTags.contains(tag)) return;
    _writeState(
      root,
      state.copyWith(badTags: [...state.badTags, tag]),
      requiredWrite: true,
    );
  }

  Future<void> _delete(Directory staging) async {
    if (await staging.exists()) await staging.delete(recursive: true);
  }

  /// Writes every entry after checking it against the signed manifest;
  /// returns why the pack is unusable, or null when every file matched.
  Future<String?> _extract(
    File zip,
    Directory target,
    EnginePackManifest manifest,
  ) async {
    final expected = {
      for (final file in manifest.files) file.name.toLowerCase(): file,
    };
    final seen = <String>{};
    final Archive archive;
    final input = InputFileStream(zip.path);
    try {
      try {
        archive = ZipDecoder().decodeStream(input);
      } on FormatException catch (e) {
        return 'The engine pack archive could not be read: ${e.message}';
      }
      for (final entry in archive) {
        if (!entry.isFile || entry.isSymbolicLink) {
          return 'The engine pack contains something that is not a file: '
              '${entry.name}';
        }
        if (!isEnginePackFileName(entry.name)) {
          return 'The engine pack contains an unsafe name: ${entry.name}';
        }
        final file = expected[entry.name.toLowerCase()];
        if (file == null) {
          return 'The engine pack contains a file that is not in the manifest: '
              '${entry.name}';
        }
        if (!seen.add(entry.name.toLowerCase())) {
          return 'The engine pack contains ${entry.name} twice.';
        }
        if (entry.size != file.size) {
          return 'The engine pack file ${entry.name} has the wrong size.';
        }
        final bytes = entry.readBytes();
        if (bytes == null || bytes.length != file.size) {
          return 'The engine pack file ${entry.name} has the wrong size.';
        }
        if (sha256.convert(bytes).toString() != file.sha256) {
          return 'The engine pack file ${entry.name} did not match its checksum.';
        }
        await File(p.join(target.path, file.name)).writeAsBytes(bytes);
      }
      if (seen.length != expected.length) {
        return 'The engine pack is missing files the manifest lists.';
      }
      return null;
    } finally {
      input.closeSync();
    }
  }

  /// Keeps the active pack and one previous one; anything older is deleted.
  Future<void> _prune(String root, String activeTag) async {
    final others = <String>[];
    final directory = Directory(root);
    if (!await directory.exists()) return;
    for (final entity in await directory.list().toList()) {
      final name = p.basename(entity.path);
      if (entity is! Directory ||
          name == activeTag ||
          File(p.join(root, '$name.delete-on-start')).existsSync() ||
          enginePackVersion(name) == null) {
        continue;
      }
      others.add(name);
    }
    others.sort((a, b) => compareEnginePackVersions(b, a));
    for (final name in others.skip(1)) {
      await Directory(p.join(root, name)).delete(recursive: true);
    }
  }
}

/// One verified candidate, kept between [EngineUpdater.check] and
/// [EngineUpdater.download].
class _PendingPack {
  final String tag;
  final EnginePackManifest manifest;
  final String zipUrl;
  final int zipSize;
  final Set<String> unavailableFiles = {};
  _PendingPack({
    required this.tag,
    required this.manifest,
    required this.zipUrl,
    required this.zipSize,
  });
}

/// File-only engine pack lookups. The model-load isolate builds one from the
/// engines root, so pack choice and the crash guard work there too.
class EnginePackFiles implements EnginePackLoader {
  EnginePackFiles(this.rootPath);

  @override
  final String rootPath;

  @override
  String? activePackDir() => _activePackDirOf(rootPath);

  @override
  int? get cudaMajor {
    final value = _readActive(rootPath)?['cudaMajor'];
    return value is int && value > 0 ? value : null;
  }

  @override
  List<String> get unavailableFiles {
    final value = _readActive(rootPath)?['unavailableFiles'];
    return value is List ? value.whereType<String>().toList() : const [];
  }

  @override
  void markLoadStarted() => _markLoadStarted(rootPath);

  @override
  void markLoadSucceeded() => _markLoadSucceeded(rootPath);
}

/// Runs only during startup preparation, before installing any loader hooks.
/// Failed deletions retain their marker and remain excluded from loading.
Future<void> _deleteScheduledPacks(String root) async {
  final directory = Directory(root);
  if (!await directory.exists()) return;
  const suffix = '.delete-on-start';
  for (final entry in await directory.list(followLinks: false).toList()) {
    final name = p.basename(entry.path);
    if (entry is! File || !name.endsWith(suffix)) continue;
    final tag = name.substring(0, name.length - suffix.length);
    if (tag != 'staging' && enginePackVersion(tag) == null) continue;
    final target = p.normalize(p.absolute(p.join(root, tag)));
    if (!p.isWithin(p.normalize(p.absolute(root)), target)) continue;
    try {
      // Never follow a substituted directory link outside the engines root.
      if (await FileSystemEntity.type(target, followLinks: false) ==
          FileSystemEntityType.link) {
        continue;
      }
      final dir = Directory(target);
      if (await dir.exists()) await dir.delete(recursive: true);
      await entry.delete();
    } on FileSystemException {
      // Retry at the next startup (e.g. another process still maps a DLL).
    }
  }
}

/// The active pack folder, or null when none is installed, the folder is
/// missing or the crash guard already reverted to the bundled engine.
String? _activePackDirOf(String root) {
  final marker = _readActive(root);
  final tag = marker?['tag'];
  final dir = marker?['dir'];
  if (tag is! String || dir is! String || enginePackVersion(tag) == null) {
    return null;
  }
  final expected = p.normalize(p.join(root, tag));
  if (!p.equals(p.normalize(dir), expected)) return null;
  if (File(p.join(root, '$tag.delete-on-start')).existsSync()) return null;
  if (!Directory(expected).existsSync()) return null;
  if (_readState(root).crashCount >= _crashLimit) return null;
  return expected;
}

void _markLoadStarted(String root) {
  final state = _readState(root);
  _writeState(
    root,
    state.copyWith(crashCount: state.crashCount + 1),
    requiredWrite: true,
  );
}

void _markLoadSucceeded(String root) {
  final state = _readState(root);
  if (state.crashCount == 0) return;
  _writeState(root, state.copyWith(crashCount: 0));
}

/// Last check, packs that must never be offered again and the crash guard.
class _State {
  final DateTime? lastCheck;
  final List<String> badTags;
  final int crashCount;
  final bool revertAcknowledged;
  const _State({
    this.lastCheck,
    this.badTags = const [],
    this.crashCount = 0,
    this.revertAcknowledged = false,
  });

  _State copyWith({
    DateTime? lastCheck,
    List<String>? badTags,
    int? crashCount,
    bool? revertAcknowledged,
  }) => _State(
    lastCheck: lastCheck ?? this.lastCheck,
    badTags: badTags ?? this.badTags,
    crashCount: crashCount ?? this.crashCount,
    revertAcknowledged: revertAcknowledged ?? this.revertAcknowledged,
  );
}

_State _readState(String root) {
  try {
    final file = File(p.join(root, 'state.json'));
    if (!file.existsSync()) return const _State();
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return const _State(crashCount: _crashLimit);
    return _State(
      lastCheck: DateTime.tryParse('${decoded['lastCheck']}'),
      badTags: (decoded['badTags'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      crashCount: (decoded['crashCount'] as num?)?.toInt() ?? 0,
      revertAcknowledged: decoded['revertAcknowledged'] == true,
    );
  } catch (_) {
    // A damaged state file must not stop the app: the defaults (bundled
    // engine, no bad tags) are always safe.
    return const _State(crashCount: _crashLimit);
  }
}

void _writeState(String root, _State state, {bool requiredWrite = false}) {
  try {
    final directory = Directory(root);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    final temp = File(p.join(root, 'state.json.tmp'));
    temp.writeAsStringSync(
      jsonEncode({
        if (state.lastCheck != null)
          'lastCheck': state.lastCheck!.toUtc().toIso8601String(),
        'badTags': state.badTags,
        'crashCount': state.crashCount,
        'revertAcknowledged': state.revertAcknowledged,
      }),
      flush: true,
    );
    final target = File(p.join(root, 'state.json'));
    temp.renameSync(target.path);
  } on FileSystemException {
    if (requiredWrite) rethrow;
    // A read-only profile keeps the bundled
    // engine instead of failing a model load.
  }
}

Map<String, dynamic>? _readActive(String root) {
  try {
    final file = File(p.join(root, 'active.json'));
    if (!file.existsSync()) return null;
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    // A damaged marker must not keep a pack active.
    return null;
  }
}

String? _activeTag(String root) {
  final tag = _readActive(root)?['tag'];
  return tag is String ? tag : null;
}

/// Replaces active.json in one rename, so a crash never leaves it half written.
Future<void> _writeActive(
  String root,
  String tag,
  String dir,
  int? cudaMajor,
  List<String> unavailableFiles,
) async {
  final temp = File(p.join(root, 'active.json.tmp'));
  await temp.writeAsString(
    jsonEncode({
      'tag': tag,
      'dir': dir,
      'cudaMajor': cudaMajor,
      'unavailableFiles': unavailableFiles,
    }),
    flush: true,
  );
  final target = File(p.join(root, 'active.json'));
  await temp.rename(target.path);
}

/// A refused request: an unexpected URL, redirect or HTTP status.
class _HttpFailure implements Exception {
  final String message;
  const _HttpFailure(this.message);

  @override
  String toString() => message;
}

/// Runs the runner's hidden probe before Flutter or the single-instance mutex.
/// Native faults only kill the child. The runner uses kBridgeExports (generated
/// by CMake) and calls od_gpu_device_count only for GPU bridges.
Future<bool> enginePackSmoke(
  String path, {
  Future<ProcessResult> Function(String, List<String>)? runProcess,
  Future<Process> Function(String, List<String>)? startProcess,
  Duration timeout = const Duration(seconds: 60),
  Duration cleanupTimeout = const Duration(seconds: 5),
}) async {
  try {
    final args = ['--engine-smoke', path];
    final ProcessResult result;
    if (runProcess != null) {
      result = await runProcess(
        Platform.resolvedExecutable,
        args,
      ).timeout(timeout);
    } else {
      final process = await (startProcess ?? Process.start)(
        Platform.resolvedExecutable,
        args,
      );
      final stdout = process.stdout.fold<BytesBuilder>(
        BytesBuilder(copy: false),
        (bytes, chunk) => bytes..add(chunk),
      );
      final stderr = process.stderr.drain<void>();
      final int code;
      try {
        code = await process.exitCode.timeout(timeout);
      } on TimeoutException {
        process.kill();
        await Future.wait([
          process.exitCode,
          stdout,
          stderr,
        ]).timeout(cleanupTimeout);
        return false;
      }
      // A descendant can hold the pipes open even after the probe exits.
      await Future.wait([stdout, stderr]).timeout(cleanupTimeout);
      result = ProcessResult(
        process.pid,
        code,
        utf8.decode((await stdout).takeBytes()),
        null,
      );
      await stderr;
    }
    if (result.exitCode != 0) return false;
    final response = jsonDecode((result.stdout as String).trim());
    return response is Map && response['ok'] == true;
  } catch (_) {
    return false;
  }
}

/// One client for the app run: the response streams outlive the call, so the
/// client cannot be closed when the future completes.
final _client =
    Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          // The redirect to the asset host is checked by the caller, never followed
          // blindly.
          followRedirects: false,
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      )
      ..httpClientAdapter = IOHttpClientAdapter(
        // GitHub refuses API calls without a User-Agent; a fixed generic name
        // says nothing about the user or the installation.
        createHttpClient: () => HttpClient()
          ..userAgent = 'on-device-llm-engine-updater'
          ..autoUncompress = false,
      );

/// The only network path: a fixed User-Agent and `Accept` go to the releases
/// API; asset downloads add their Range when resuming.
Future<EngineHttpResponse> _dioFetch(Uri uri, {String? range}) async {
  final response = await _client.getUri<ResponseBody>(
    uri,
    options: Options(
      responseType: ResponseType.stream,
      headers: {
        // HttpClient offers gzip by default, but autoUncompress is off (the
        // pack hashes cover the bytes as sent), so ask for the plain body.
        'Accept-Encoding': 'identity',
        if (uri.host == 'api.github.com')
          'Accept': 'application/vnd.github+json',
        if (range != null) 'Range': 'bytes=$range-',
      },
    ),
  );
  final status = response.statusCode ?? 0;
  final body = response.data;
  // A redirect body is never read; draining it closes the transfer.
  if (status >= 300 && status < 400) await body?.stream.drain<void>();
  return EngineHttpResponse(
    status,
    location: response.headers.value('location'),
    body: status >= 300 && status < 400
        ? const Stream<List<int>>.empty()
        : body?.stream ?? const Stream<List<int>>.empty(),
  );
}
