import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/quiet_failure.dart';
import '../../core/platform/build_identity.dart';
import '../../core/platform/engine_versions.dart';
import '../../inference/engine/engine_descriptor.dart';
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

/// The plan allows one automatic check a day per installation.
const _checkInterval = Duration(hours: 24);

/// Two loads that never finished mean the pack is broken.
const _crashLimit = 2;

/// Marker file suffix for a folder that must be deleted at the next startup
/// because this process may still map a DLL from it.
const deleteOnStartSuffix = '.delete-on-start';

/// Suffix of a legacy install moved aside while its signed replacement is
/// promoted. Never a pack folder name, so no lookup can select it.
const _legacySuffix = '.legacy';

/// Suffix of a half-promoted folder put aside by a failed restore. Never a
/// pack folder name either; deleted best-effort or at the next startup.
const _brokenSuffix = '.broken';

/// The lock file serialising state.json and active.json updates.
const _lockFileName = 'pack.lock';

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

/// Why a check or install failed. The panel maps it to a localized message;
/// [EngineCheckResult.message] keeps only diagnostic detail for the log, so no
/// raw exception text is ever shown in the UI (release review P2 l10n).
enum EngineUpdateProblem {
  /// No ik_llama.cpp commit is pinned in this app build.
  noPinnedBuild,

  /// [EngineUpdater.download] ran without a pack found by [EngineUpdater.check].
  noUpdateAvailable,

  /// The release list or one of its assets could not be fetched or read.
  checkFailed,

  /// The download, its signed checksum or the extraction failed.
  downloadFailed,

  /// The pack was extracted but failed its CPU smoke test.
  smokeFailed,

  /// The verified pack could not be promoted into its engines folder.
  installFailed,

  /// Switching back to the bundled engine could not write its state.
  useBundledFailed,

  /// Deleting the downloaded engines could not be scheduled.
  removeFailed,
}

/// What one check found: nothing new, a verified pack with its download size,
/// no network, or a typed failure (see [EngineUpdateProblem]).
class EngineCheckResult {
  final EngineCheckState state;
  final String? tag;
  final int? size;

  /// Diagnostic detail for the log, never shown in the UI.
  final String? message;

  /// The localized failure the panel shows; null unless [state] is an error.
  final EngineUpdateProblem? problem;
  final DateTime? lastCheck;
  const EngineCheckResult(
    this.state, {
    this.tag,
    this.size,
    this.message,
    this.problem,
    this.lastCheck,
  });
}

enum EngineDownloadState { done, cancelled, error }

class EngineDownloadResult {
  final EngineDownloadState state;

  /// Diagnostic detail for the log, never shown in the UI.
  final String? message;

  /// The localized failure the panel shows; null unless [state] is an error.
  final EngineUpdateProblem? problem;
  const EngineDownloadResult(this.state, {this.message, this.problem});
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

  /// Which engine's packs this updater verifies and installs. Each kind has
  /// its own tag shape, asset names and folder under the engines root.
  final EnginePackKind kind;

  /// Test override for the full ik commit as a tag. Production uses [EnginePins].
  final String? pinnedTag;

  /// Engines root; the default is `<application support dir>/engines`, with
  /// the kind's folder appended for engines other than llama.cpp.
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
    this.kind = EnginePackKind.llamaCpp,
    this.pinnedTag,
    this.root,
  }) : fetch = fetch ?? _dioFetch,
       openSmoke = openSmoke ?? enginePackSmoke,
       clock = clock ?? DateTime.now,
       appVersion = appVersion ?? BuildIdentity.version;

  /// Resolves the engines folder and installs the loader hooks; call it at
  /// startup so the first model load can already use a downloaded pack. The
  /// saved manifest's signature is checked here, so a swapped manifest (which
  /// the synchronous load path cannot re-sign) is refused before any load.
  Future<void> prepare() async {
    await _rootPath();
    await _files!.prepare();
  }

  /// ik_llama.cpp pack commit: the full 40 characters from [pinnedTag] when a
  /// test injects one, otherwise the compiled pin. Null for llama.cpp.
  String? get _pinCommit {
    if (kind == EnginePackKind.llamaCpp) return null;
    final override = kind.parseTag(pinnedTag)?.engine;
    return override != null && override.length == 40
        ? override
        : EnginePins.ikLlamaCommit;
  }

  /// Checks for a newer verified pack at most once a day. [manual] is the
  /// user's own request (Check now / Install): it ignores the stored interval
  /// and may retry a tag an earlier smoke failure, interruption or crash
  /// excluded from automatic checks.
  /// Startup migration uses [ignoreInterval] to bypass the interval and may
  /// reinstall the active legacy tag at the floor. All automatic exclusions
  /// still apply.
  Future<EngineCheckResult> check({
    bool manual = false,
    bool ignoreInterval = false,
  }) async {
    final root = await _rootPath();
    final state = _readState(root);
    final last = state.lastCheck;
    final now = clock();
    if (!manual &&
        !ignoreInterval &&
        last != null &&
        now.difference(last) < _checkInterval) {
      return EngineCheckResult(EngineCheckState.upToDate, lastCheck: last);
    }
    _pending = null;
    // Failed checks also count, avoiding repeated automatic network attempts.
    _updateState(root, (current) => current.copyWith(lastCheck: now));
    final List<int> body;
    try {
      body = await _body(await fetch(Uri.parse(_releasesUrl)));
    } on _HttpFailure catch (e) {
      return EngineCheckResult(
        EngineCheckState.error,
        message: e.message,
        problem: EngineUpdateProblem.checkFailed,
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
        problem: EngineUpdateProblem.checkFailed,
        lastCheck: now,
      );
    }
    if (releases is! List) {
      return EngineCheckResult(
        EngineCheckState.error,
        message: 'The release list was not a list.',
        problem: EngineUpdateProblem.checkFailed,
        lastCheck: now,
      );
    }
    final pinnedCommit = _pinCommit;
    final candidates = <({String tag, Map<dynamic, dynamic> release})>[];
    for (final item in releases) {
      if (item is! Map) continue;
      final tag = item['tag_name'];
      if (tag is! String) continue;
      final version = kind.parseTag(tag);
      if (version == null ||
          (pinnedCommit != null && !pinnedCommit.startsWith(version.engine))) {
        continue;
      }
      candidates.add((tag: tag, release: item));
    }
    // Newest build first; the first candidate that verifies and fits wins.
    candidates.sort(
      (a, b) => kind.compareTags(b.tag, a.tag, pin: pinnedCommit),
    );

    // Only a pack whose files still match its saved manifest counts as
    // installed: a tampered pack or one from a moved pin must not stop the
    // check from offering the same tag again.
    await _files!.prepare();
    final activeDir = _files!.verifiedPackDir();
    final activeTag = activeDir == null ? null : p.basename(activeDir);
    final markedDir = ignoreInterval ? _markedPackDir(root, kind) : null;
    final legacyTag = markedDir != null && _files!.isLegacyInstall(markedDir)
        ? p.basename(markedDir)
        : null;
    final currentState = _readState(root);
    // The anti-rollback floor is the newest signed install, kept in state even
    // when the active pack itself no longer verifies: migration must never
    // install an older signed release over it (P2 re-review).
    final bundled = llamaBuildNumber(EnginePins.llamaCppTag) ?? 0;
    // ik_llama packs are only built from the pinned commit; a tag from another
    // commit belongs to a build this app knows nothing about. Tests inject
    // [pinnedTag], production uses the compiled pin.
    for (final candidate in candidates) {
      final tag = candidate.tag;
      // A manual check can retry tags excluded by a smoke failure, an
      // interrupted install or the crash guard.
      if (!manual &&
          (currentState.inFlightTag == tag ||
              currentState.badTags.contains(tag) ||
              currentState.failedTags.contains(tag) ||
              currentState.interruptedTags.contains(tag))) {
        continue;
      }
      final version = kind.parseTag(tag)!;
      if (kind == EnginePackKind.llamaCpp &&
          compareEnginePackVersions(tag, 'engine-b$bundled') <= 0) {
        continue;
      }
      if (_belowRevisionFloor(root, tag, currentState, kind, pinnedCommit)) {
        continue;
      }
      // An automatic check must never bring back the release the user just
      // left: only a tag strictly newer than the stored floor may be installed
      // by itself, except when migrating that exact active legacy tag.
      if (!manual &&
          tag != legacyTag &&
          _notNewerThanFloor(root, tag, currentState, kind, pinnedCommit)) {
        continue;
      }
      // A verified active pack blocks its own and older revisions. An active
      // pack that no longer verifies may be reinstalled from its signed
      // release at the same tag and revision (migration included).
      if (activeTag != null &&
          kind.compareTags(tag, activeTag, pin: pinnedCommit) <= 0) {
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
          problem: EngineUpdateProblem.checkFailed,
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
      // The manifest always names the full pinned commit for ik_llama.cpp,
      // even when the tag uses a shorter prefix.
      final sameEngine = kind == EnginePackKind.llamaCpp
          ? manifest.engine == version.engine
          : manifest.engine == pinnedCommit;
      if (manifest.kind != kind ||
          !sameEngine ||
          manifest.revision != version.revision ||
          !manifest.compatible(appVersion: appVersion, bridgeApi: bridgeApi)) {
        continue;
      }
      _pending = _PendingPack(
        tag: tag,
        manifest: manifest,
        manifestBytes: manifestBytes,
        signature: signature,
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
        problem: EngineUpdateProblem.noUpdateAvailable,
      );
    }
    _ready = null;
    final root = await _rootPath();
    final staging = Directory(p.join(root, 'staging', pending.tag));
    final part = File(p.join(staging.path, 'pack.zip.part'));
    final zip = File(p.join(staging.path, 'pack.zip'));
    var verifying = false;
    try {
      _updateState(
        root,
        (state) => state.copyWith(inFlightTag: pending.tag),
        requiredWrite: true,
      );
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
        _recordInterruptedTag(root, pending.tag);
        return const EngineDownloadResult(EngineDownloadState.cancelled);
      }
      verifying = true;
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != pending.manifest.zipSha256) {
        _recordInterruptedTag(root, pending.tag);
        await _discardStaging(staging);
        return const EngineDownloadResult(
          EngineDownloadState.error,
          message: 'The engine pack zip did not match its signed checksum.',
          problem: EngineUpdateProblem.downloadFailed,
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
        _recordInterruptedTag(root, pending.tag);
        await _discardStaging(staging);
        return EngineDownloadResult(
          EngineDownloadState.error,
          message: problem,
          problem: EngineUpdateProblem.downloadFailed,
        );
      }
      if (await zip.exists()) await zip.delete();
      final cpuFiles = pending.manifest.files
          .where((file) => LlamaBindings.windowsCpuOf(file.name) != null)
          .toList();
      if (cpuFiles.isEmpty) {
        // A signed pack without a CPU bridge is a verification failure: the
        // exclusion is persisted before the staging is removed (P2).
        _recordInterruptedTag(root, pending.tag);
        await _discardStaging(staging);
        return const EngineDownloadResult(
          EngineDownloadState.error,
          message: 'The engine pack has no CPU bridge.',
          problem: EngineUpdateProblem.downloadFailed,
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
        // Persist the smoke failure before cleaning up staging so automatic
        // checks skip this tag. A manual retry runs the smoke test again.
        _addBadTag(root, pending.tag);
        await _discardStaging(staging);
        return const EngineDownloadResult(
          EngineDownloadState.error,
          message: 'The engine pack failed its smoke test.',
          problem: EngineUpdateProblem.smokeFailed,
        );
      }
      // GPU runtimes are optional. CPU validation is complete, so a GPU probe
      // must not blacklist an otherwise usable pack. The in-flight marker stays
      // through these probes: a crash here is an interrupted install too (P2).
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
    } catch (e) {
      try {
        if (verifying) {
          _recordInterruptedTag(root, pending.tag);
        } else {
          // Let the next automatic check retry a failed transfer.
          _updateState(
            root,
            (state) => state.inFlightTag == pending.tag
                ? state.copyWith(clearInFlight: true)
                : state,
            requiredWrite: true,
          );
        }
        if (e is _HttpFailure) await _discardStaging(staging);
      } on FileSystemException catch (error, stack) {
        // The in-flight marker still excludes the tag from automatic checks.
        quietFailure('engine_updater:interruption-record', error, stack);
      }
      return EngineDownloadResult(
        EngineDownloadState.error,
        message: e is _HttpFailure
            ? e.message
            : 'The engine pack download failed: $e',
        problem: EngineUpdateProblem.downloadFailed,
      );
    }
  }

  /// Promotes the verified staging pack; the change applies on the next model
  /// load. Returns false when no downloaded pack is waiting, or when the
  /// promoted files no longer match the signed manifest.
  Future<bool> activate({String? tag}) async {
    final root = await _rootPath();
    final ready = _ready;
    final wanted = tag ?? ready?.tag;
    if (ready == null || wanted == null || wanted != ready.tag) return false;
    final staging = Directory(p.join(root, 'staging', wanted));
    if (!await staging.exists()) return false;
    // Recheck the exact staged set immediately before promotion: only the
    // files the signed manifest lists, each with its signed hash.
    if (!await verifyPackContent(staging.path, ready.manifest)) {
      // An activation hash failure is a verification failure: the retry
      // exclusion is persisted before the staging is removed (P2).
      _recordInterruptedTag(root, wanted);
      await _discardStaging(staging);
      _ready = null;
      return false;
    }
    final previous = _files!.verifiedPackDir();
    final target = Directory(p.join(root, wanted));
    // Final renames, verification and marker publication share the pack lock
    // with crash rollback and startup recovery. Hash large DLLs off the UI.
    final quarantine = _quarantinePath(root, wanted);
    final promoted = await _promotePackInWorker(
      root: root,
      kind: kind,
      pin: _pinCommit ?? EnginePins.ikLlamaCommit,
      tag: wanted,
      staging: staging.path,
      target: target.path,
      quarantine: quarantine,
      manifest: ready.manifest,
      manifestBytes: ready.manifestBytes,
      signature: ready.signature,
      unavailableFiles: ready.unavailableFiles.toList(),
    ).whenComplete(() => _cleanQuarantine(quarantine));
    if (!promoted) {
      if (!await staging.exists()) _ready = null;
      return false;
    }
    _files!._remember(
      target.path,
      ready.manifest,
      ready.manifestBytes,
      ready.signature,
      contentVerified: true,
    );
    _files!._legacy.clear();
    _pending = null;
    _ready = null;
    try {
      await _prune(root, wanted, previous: previous);
    } on FileSystemException catch (e, st) {
      quietFailure('engine_updater:prune', e, st);
    }
    return true;
  }

  /// Reverts to the bundled engine and clears the crash markers.
  Future<void> useBundled() async {
    _ready = null;
    final root = await _rootPath();
    // The crash guard in the model-load isolate writes the marker under the
    // same lock: deleting it outside would let a rollback resurrect a marker
    // the user just removed (P3-2).
    _withPackLock(root, () {
      final state = _readState(root);
      final marker = _readActive(root);
      final markerTag = marker?['tag'];
      final pin = _pinCommit ?? EnginePins.ikLlamaCommit;
      final floor = _revisionFloor(root, state, kind, pin);
      // The tag the user is leaving becomes the anti-rollback floor, even when
      // a legacy marker carries no verifiedTag of its own: without it the next
      // automatic check could reinstall the release the user just left. It is
      // written under the lock before the marker is deleted (P2).
      var optedOut = floor;
      if (marker?['verifiedTag'] is! String &&
          markerTag is String &&
          kind.parseTag(markerTag) != null &&
          (floor == null || kind.compareTags(markerTag, floor, pin: pin) > 0)) {
        optedOut = markerTag;
      }
      _writeStateLocked(
        root,
        state.copyWith(
          verifiedTag: optedOut,
          crashCount: 0,
          // The failed and interrupted tags are kept: switching to the
          // built-in engine must not let the automatic check reinstall the tag
          // the user left. A manual check can still offer it (P1, P2).
          clearUnverified: true,
        ),
        requiredWrite: optedOut != state.verifiedTag,
      );
      final active = File(p.join(root, 'active.json'));
      if (active.existsSync()) active.deleteSync();
    }, required: true);
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
          (!kind.ownsFolder(name) && name != 'staging')) {
        continue;
      }
      await File(
        p.join(root, '$name.delete-on-start'),
      ).writeAsString('', flush: true);
    }
  }

  /// The loader's active pack folder, or null for the bundled engine. Cheap:
  /// it checks the marker, not the DLL hashes, so UI refreshes stay fast.
  String? activePackDir() => _files?.activePackDir();

  /// The active pack folder after every DLL matched the saved signed manifest;
  /// null means the load must fall back to the bundled engine.
  String? verifiedPackDir() => _files?.verifiedPackDir();

  /// True when a pack folder (active, reverted, unverified or scheduled for
  /// deletion) or the staging folder is still on disk. The panel keeps its
  /// removal row visible from this, whatever the revert notice says (P2).
  Future<bool> packFilesOnDisk() async {
    final root = await _rootPath();
    try {
      await for (final entity in Directory(root).list(followLinks: false)) {
        final name = p.basename(entity.path);
        if (entity is Directory &&
            (kind.ownsFolder(name) || name == 'staging')) {
          return true;
        }
      }
    } on FileSystemException catch (e, st) {
      quietFailure('engine_updater:pack-files', e, st);
    }
    return false;
  }

  /// True when the installed pack's manifest no longer verifies (or never had
  /// one). The panel shows the localized notice; the next load refuses it.
  bool get unverifiedNotice {
    final root = _rootDir;
    return root != null && _readState(root).unverifiedTag != null;
  }

  /// True when the active folder predates the copied manifest (P2-2). The
  /// controller re-offers its tag instead of silently using the bundled engine.
  bool get needsMigration => _files?.needsMigration ?? false;

  /// Written before a load from the pack and cleared after it succeeded.
  /// Returns false when the attempt could not be recorded: the caller must
  /// then refuse the pack for this load (P3-2).
  bool markLoadStarted() => _files?.markLoadStarted() ?? true;
  void markLoadSucceeded() => _files?.markLoadSucceeded();

  /// When the last check ran (automatic or forced), for Settings.
  DateTime? get lastCheck {
    final root = _rootDir;
    return root == null ? null : _readState(root).lastCheck;
  }

  /// True after two unfinished loads from the pack, until the user
  /// acknowledges the revert.
  bool get revertedNotice {
    final root = _rootDir;
    if (root == null) return false;
    final state = _readState(root);
    return (state.crashCount >= _crashLimit || state.failedTags.isNotEmpty) &&
        !state.revertAcknowledged;
  }

  void acknowledgeRevert() {
    final root = _rootDir;
    if (root == null) return;
    _updateState(root, (state) => state.copyWith(revertAcknowledged: true));
  }

  /// Rebuilds the loader hooks in the model-load isolate, which only receives
  /// the engines root as a plain path.
  static void installIsolateLoader(String rootPath) {
    final root = p.normalize(p.absolute(rootPath));
    LlamaBindings.enginePack = EnginePackFiles(root);
    LlamaBindings.ikEnginePack = EnginePackFiles(
      p.join(root, EnginePackKind.ikLlama.folder),
      kind: EnginePackKind.ikLlama,
    );
  }

  Future<String> _rootPath() async {
    final cached = _rootDir;
    if (cached != null) return cached;
    final base =
        root ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'engines'),
        );
    final directory = kind.folder.isEmpty
        ? base
        : Directory(p.join(base.path, kind.folder));
    final path = p.normalize(p.absolute(directory.path));
    await _recoverLegacyPacks(path, kind);
    await _deleteScheduledPacks(path, kind);
    // A quit or a crash during installation leaves its in-flight marker here.
    await _recoverInFlight(path, kind);
    _rootDir = path;
    _files ??= EnginePackFiles(
      path,
      kind: kind,
      pinnedCommit: _pinCommit ?? EnginePins.ikLlamaCommit,
      signingPublicKey: signingPublicKey,
      appVersion: appVersion,
      bridgeApi: bridgeApi,
    );
    for (final tag in _readState(path).badTags) {
      if (kind.parseTag(tag) != null) {
        // A rejected pack's staging is deleted best-effort: the tag is already
        // excluded from automatic checks, so a folder that cannot be removed
        // now must not stop the app from starting.
        await _discardStaging(Directory(p.join(path, 'staging', tag)));
      }
    }
    // The loader runs in this isolate too (probing, estimates), so it must see
    // the same pack as the settings page.
    if (kind == EnginePackKind.llamaCpp) {
      LlamaBindings.enginePack = _files;
    } else {
      LlamaBindings.ikEnginePack = _files;
    }
    return path;
  }

  /// Authenticates the saved manifests for the engine this worker will use.
  static Future<void> prepareIsolatePack(String engineId) async {
    final loader = engineId == ikLlamaEngineId
        ? LlamaBindings.ikEnginePack
        : LlamaBindings.enginePack;
    if (loader is EnginePackFiles) await loader.prepare();
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

    final manifest = url(kind.manifestAsset);
    final signature = url(kind.signatureAsset);
    final zip = url(kind.zipAsset);
    if (manifest == null || signature == null || zip == null) return null;
    for (final value in [manifest, signature, zip]) {
      if (!value.startsWith(_assetPrefix)) return null;
    }
    final size = byName[kind.zipAsset]?['size'];
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

  /// Records a CPU smoke-test failure to exclude the tag from automatic checks.
  void _addBadTag(String root, String tag) {
    _updateState(root, (state) {
      return state.copyWith(
        badTags: state.badTags.contains(tag)
            ? state.badTags
            : [...state.badTags, tag],
        clearInFlight: state.inFlightTag == tag,
      );
    }, requiredWrite: true);
  }

  Future<void> _delete(Directory staging) async {
    await _deletePackDirectory(staging.path);
  }

  /// Deletes a staging folder whose pack was already rejected. The failure is
  /// recorded in state.json first, so a folder that cannot be removed now must
  /// not turn that rejection back into a retryable interruption.
  Future<void> _discardStaging(Directory staging) async {
    try {
      await _delete(staging);
    } on FileSystemException catch (e, st) {
      // Startup recovery and the bad-tag sweep remove it at the next start.
      quietFailure('engine_updater:staging-cleanup', e, st);
    }
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
  Future<void> _prune(String root, String activeTag, {String? previous}) async {
    final others = <String>[];
    final directory = Directory(root);
    if (!await directory.exists()) return;
    for (final entity in await directory.list(followLinks: false).toList()) {
      final name = p.basename(entity.path);
      if (entity is! Directory ||
          name == activeTag ||
          File(p.join(root, '$name.delete-on-start')).existsSync() ||
          !kind.ownsFolder(name)) {
        continue;
      }
      others.add(name);
    }
    others.sort((a, b) => kind.compareTags(b, a, pin: _pinCommit));
    final failedTags = _readState(root).failedTags;
    final keep =
        kind == EnginePackKind.ikLlama &&
            previous != null &&
            p.basename(previous) != activeTag
        ? p.basename(previous)
        : others.where((tag) => !failedTags.contains(tag)).firstOrNull;
    final pruned = _withPackLock(root, () {
      if (_readActive(root)?['tag'] != activeTag) return <String>[];
      final quarantines = <String>[];
      for (final name in others) {
        if (name == keep) continue;
        final dir = Directory(p.join(root, name));
        final quarantine = _quarantinePath(root, name);
        if (_quarantinePack(dir, quarantine)) quarantines.add(quarantine);
      }
      return quarantines;
    }, required: true);
    for (final path in pruned) {
      await _cleanQuarantine(path);
    }
  }
}

/// One verified candidate, kept between [EngineUpdater.check] and
/// [EngineUpdater.download].
class _PendingPack {
  final String tag;
  final EnginePackManifest manifest;

  /// The exact signed manifest bytes and signature, copied into the installed
  /// folder so a later load can hash the DLLs against them.
  final List<int> manifestBytes;
  final List<int> signature;
  final String zipUrl;
  final int zipSize;
  final Set<String> unavailableFiles = {};
  _PendingPack({
    required this.tag,
    required this.manifest,
    required this.manifestBytes,
    required this.signature,
    required this.zipUrl,
    required this.zipSize,
  });
}

/// File-only engine pack lookups. The model-load isolate builds one from the
/// engines root, so pack choice and the crash guard work there too.
class EnginePackFiles implements EnginePackLoader {
  EnginePackFiles(
    this.rootPath, {
    this.kind = EnginePackKind.llamaCpp,
    this.pinnedCommit = EnginePins.ikLlamaCommit,
    this.signingPublicKey = kEngineSigningPublicKey,
    this.appVersion = BuildIdentity.version,
    this.bridgeApi = kEngineBridgeApi,
    this.beforeCrashRollback,
  });

  @override
  final String rootPath;

  /// Which engine's pack folders and active marker this root holds.
  final EnginePackKind kind;

  /// Full 40-character ik_llama.cpp commit an installed pack must name. The
  /// model-load isolate rebuilds this loader with the compiled pin.
  final String pinnedCommit;

  final String signingPublicKey;
  final String appVersion;
  final int bridgeApi;
  @visibleForTesting
  final void Function()? beforeCrashRollback;
  final _manifests =
      <
        String,
        ({
          EnginePackManifest manifest,
          Digest manifestHash,
          Digest signatureHash,
        })
      >{};

  /// Packs whose DLLs matched their signed manifest (manifest and signature
  /// hashes). The entry is only written by [prepare] (or by activation, after
  /// the promoted folder was re-hashed), and every native open re-hashes the
  /// file it is about to load, so a stat is never trusted (P2 re-review).
  final _verified = <String, _VerifiedPack>{};

  /// Stat fingerprint of the last content check per folder, so an unchanged
  /// pack is not read again on every prepare (P2-2). The DLL bytes are still
  /// hashed under the lock at each native open, which is the gate that matters.
  final _contentChecks = <String, _ContentCheck>{};

  /// Real content-hash runs; a memo hit performs none (P2-2). Test-only.
  int _contentHashRuns = 0;

  @visibleForTesting
  int get contentHashRuns => _contentHashRuns;

  /// Active folders installed before the manifest/signature were copied in
  /// (P2-2). They stay on disk and inactive until a signed reinstall succeeds.
  final _legacy = <String>{};

  /// True when an active pack predates the installed manifest. The controller
  /// re-offers its tag instead of silently swapping to the bundled engine.
  bool get needsMigration => _legacy.isNotEmpty;

  /// True when [dir] is the active folder of an install that predates the
  /// copied signed manifest.
  bool isLegacyInstall(String dir) => _legacy.contains(dir);

  /// The signed manifest's SHA-256 for [name] of the verified pack [dir], or
  /// null when the pack does not list that file. The loader re-hashes the
  /// file against this while it holds a no-write/no-delete lock on it.
  @override
  String? expectedFileSha256(String dir, String name) {
    final manifest = _manifests[dir]?.manifest;
    if (manifest == null) return null;
    final wanted = name.toLowerCase();
    for (final file in manifest.files) {
      if (file.name.toLowerCase() == wanted) return file.sha256;
    }
    return null;
  }

  void _remember(
    String dir,
    EnginePackManifest manifest,
    List<int> bytes,
    List<int> signature, {
    bool contentVerified = false,
  }) {
    final manifestHash = sha256.convert(bytes);
    final signatureHash = sha256.convert(signature);
    _manifests[dir] = (
      manifest: manifest,
      manifestHash: manifestHash,
      signatureHash: signatureHash,
    );
    if (contentVerified) {
      _legacy.remove(dir);
      _verified[dir] = _VerifiedPack(manifestHash, signatureHash);
      // The promotion just hashed this folder: remember its stat fingerprint
      // so the next prepare does not read the pack again (P2-2).
      _contentChecks[dir] = _ContentCheck(
        _fingerprint(dir, manifestHash, signatureHash),
        true,
      );
    }
  }

  /// Names, sizes and modification times of every file in [dir], bound to the
  /// authenticated manifest/signature hashes. Any change of the pack changes
  /// it, so the memoised content result is recomputed; an unreadable folder
  /// returns null and is hashed as before.
  String? _fingerprint(String dir, Digest manifestHash, Digest signatureHash) {
    try {
      final entries = <String>[];
      for (final entity in Directory(dir).listSync(followLinks: false)) {
        if (entity is! File) return null;
        entries.add(
          '${p.basename(entity.path).toLowerCase()}'
          '\u0000${entity.lengthSync()}'
          '\u0000${entity.lastModifiedSync().microsecondsSinceEpoch}',
        );
      }
      entries.sort();
      return '$manifestHash\u0000$signatureHash\u0000${entries.join('\u0001')}';
    } catch (e, st) {
      quietFailure('engine_updater:pack-fingerprint', e, st);
      return null;
    }
  }

  /// Authenticate manifests before a synchronous load can use them. Keep the
  /// exact bytes bound to the parsed manifest in this isolate, never in state.json.
  Future<void> prepare() async {
    final dirs = <String>{};
    final active = _markedPackDir(rootPath, kind);
    if (active != null) dirs.add(active);
    if (kind == EnginePackKind.ikLlama && Directory(rootPath).existsSync()) {
      for (final entry in Directory(rootPath).listSync(followLinks: false)) {
        if (entry is Directory && kind.ownsFolder(p.basename(entry.path))) {
          dirs.add(entry.path);
        }
      }
    }
    _manifests.removeWhere((dir, _) => !dirs.contains(dir));
    _verified.removeWhere((dir, _) => !dirs.contains(dir));
    _contentChecks.removeWhere((dir, _) => !dirs.contains(dir));
    _legacy.clear();
    for (final dir in dirs) {
      final tag = p.basename(dir);
      final version = kind.parseTag(tag);
      if (version == null) continue;
      try {
        final manifestFile = File(p.join(dir, installedManifestName));
        final signatureFile = File(p.join(dir, installedSignatureName));
        if (!await manifestFile.exists() || !await signatureFile.exists()) {
          // A pack installed by an earlier build has no copied manifest yet.
          // Keep it on disk: the next check re-offers the same tag, and while
          // the reinstall is pending the panel shows the unverified notice.
          _manifests.remove(dir);
          _verified.remove(dir);
          if (dir == active) {
            _legacy.add(dir);
            _markUnverified(rootPath, tag);
            // The legacy folder still holds a real install: its revision is
            // the anti-rollback floor until the signed reinstall lands, so a
            // check in between cannot offer an older revision (P3-3).
            _noteVerified(rootPath, tag, kind, pinnedCommit);
          }
          continue;
        }
        final bytes = await manifestFile.readAsBytes();
        final signature = await signatureFile.readAsBytes();
        final manifestHash = sha256.convert(bytes);
        final signatureHash = sha256.convert(signature);
        var trusted = _manifests[dir];
        if (trusted == null ||
            trusted.manifestHash != manifestHash ||
            trusted.signatureHash != signatureHash) {
          _manifests.remove(dir);
          _verified.remove(dir);
          final manifest = EnginePackManifest.parse(bytes);
          final engineMatches = kind == EnginePackKind.ikLlama
              ? manifest.engine == pinnedCommit &&
                    pinnedCommit.startsWith(version.engine)
              : manifest.engine == version.engine;
          if (engineMatches &&
              manifest.kind == kind &&
              manifest.revision == version.revision &&
              manifest.loadCompatible(bridgeApi: bridgeApi) &&
              await verifySignature(
                bytes,
                signature,
                publicKey: signingPublicKey,
              )) {
            _remember(dir, manifest, bytes, signature);
            trusted = _manifests[dir]!;
          } else {
            if (dir == active) _markUnverified(rootPath, tag);
            continue;
          }
        }
        // Every prepare re-hashes the DLLs off this isolate unless the folder
        // is unchanged since the last check: a stat fingerprint (names, sizes,
        // modification times, authenticated manifest) decides that, and any
        // change re-hashes (P2-2). A stat alone still proves nothing about the
        // bytes, because every native open hashes the file it maps.
        final fingerprint = _fingerprint(
          dir,
          trusted.manifestHash,
          trusted.signatureHash,
        );
        final memo = _contentChecks[dir];
        if (memo != null &&
            fingerprint != null &&
            memo.fingerprint == fingerprint) {
          _verified.remove(dir);
          if (memo.verified) {
            _verified[dir] = _VerifiedPack(manifestHash, signatureHash);
            if (dir == active) _noteVerified(rootPath, tag, kind, pinnedCommit);
          } else if (dir == active) {
            _markUnverified(rootPath, tag);
          }
          continue;
        }
        _verified.remove(dir);
        final verified = await _verifyPackContent(dir, trusted.manifest);
        _contentHashRuns++;
        _contentChecks[dir] = _ContentCheck(fingerprint, verified);
        if (verified) {
          _verified[dir] = _VerifiedPack(manifestHash, signatureHash);
          if (dir == active) _noteVerified(rootPath, tag, kind, pinnedCommit);
        } else if (dir == active) {
          _markUnverified(rootPath, tag);
        }
      } catch (e, st) {
        quietFailure('engine_updater:verify-manifest', e, st);
        _manifests.remove(dir);
        _verified.remove(dir);
        if (dir == active) _markUnverified(rootPath, tag);
      }
    }
  }

  @override
  String? activePackDir() {
    final dir = _markedPackDir(rootPath, kind);
    if (dir == null) return null;
    final state = _readState(rootPath);
    final tag = p.basename(dir);
    if (state.crashCount >= _crashLimit || state.failedTags.contains(tag)) {
      if (kind != EnginePackKind.ikLlama) return null;
      beforeCrashRollback?.call();
      return _revertCrashedPack(tag);
    }
    return dir;
  }

  @override
  String? verifiedPackDir() {
    final dir = activePackDir();
    if (dir == null) return null;
    final tag = p.basename(dir);
    if (!_verifyPackDir(dir)) {
      _markUnverified(rootPath, tag);
      return null;
    }
    _clearUnverified(rootPath, tag);
    return dir;
  }

  /// Cheap synchronous check of the pack's shape: only the files the signed
  /// manifest lists, and the manifest/signature bytes that were authenticated
  /// in this isolate. The DLL bytes are re-hashed by [prepare] and again, under
  /// a write lock, at every native open (P2 re-review).
  bool _verifyPackDir(String dir) {
    final trusted = _manifests[dir];
    final verified = _verified[dir];
    if (trusted == null || verified == null) return false;
    try {
      final expected = {
        for (final file in trusted.manifest.files)
          file.name.toLowerCase(): file,
      };
      if (FileSystemEntity.typeSync(dir, followLinks: false) !=
          FileSystemEntityType.directory) {
        return false;
      }
      final seen = <String>{};
      for (final entity in Directory(dir).listSync(followLinks: false)) {
        if (entity is! File) return false;
        final name = p.basename(entity.path).toLowerCase();
        if (name == installedManifestName ||
            name == installedSignatureName ||
            name == installedMetaName) {
          continue;
        }
        final file = expected[name];
        // A size that no longer matches the manifest refuses the pack; the
        // size is only ever used to refuse, never to accept.
        if (file == null ||
            !seen.add(name) ||
            entity.lengthSync() != file.size) {
          return false;
        }
      }
      if (seen.length != expected.length) return false;
      // The manifest and signature are kilobytes, so hashing them here stays
      // cheap and keeps the exact signed bytes authenticated at load time.
      return _sha256File(File(p.join(dir, installedManifestName))) ==
              verified.manifestHash &&
          _sha256File(File(p.join(dir, installedSignatureName))) ==
              verified.signatureHash;
    } catch (e, st) {
      quietFailure('engine_updater:verify-pack', e, st);
      return false;
    }
  }

  /// Hashes every DLL of [dir] against [manifest] in a worker isolate, so a
  /// large bridge is never read on the calling (UI) isolate. Runs before a
  /// load, after a staged pack is promoted and when a pack is prepared.
  Future<bool> _verifyPackContent(String dir, EnginePackManifest manifest) =>
      verifyPackContent(dir, manifest);

  String? _revertCrashedPack(String failedTag) {
    try {
      return _withPackLock(rootPath, () {
        final active = _readActive(rootPath);
        if (active?['tag'] != failedTag) return null;
        final state = _readState(rootPath);
        if (state.crashCount < _crashLimit &&
            !state.failedTags.contains(failedTag)) {
          return _markedPackDir(rootPath, kind);
        }
        final candidates = _manifests.keys.where((dir) {
          final tag = p.basename(dir);
          return kind.compareTags(tag, failedTag, pin: pinnedCommit) < 0 &&
              !state.failedTags.contains(tag) &&
              !state.badTags.contains(tag) &&
              !File(p.join(rootPath, '$tag$deleteOnStartSuffix')).existsSync();
        }).toList();
        candidates.sort(
          (a, b) =>
              kind.compareTags(p.basename(b), p.basename(a), pin: pinnedCommit),
        );
        final previous = candidates.where(_verifyPackDir).firstOrNull;
        // If switching the marker fails, the failed tag lets the next lookup
        // retry the rollback. Carry the revision floor across the switch.
        if (!state.failedTags.contains(failedTag)) {
          _writeStateLocked(
            rootPath,
            state.copyWith(
              crashCount: 0,
              failedTag: failedTag,
              revertAcknowledged: false,
            ),
            requiredWrite: true,
          );
        }
        if (previous != null) {
          final floor = active?['verifiedTag'];
          _writeActiveLocked(
            rootPath,
            p.basename(previous),
            previous,
            _manifests[previous]!.manifest.cudaMajor,
            _readPackMeta(previous),
            verifiedTag: floor is String ? floor : null,
          );
        }
        return previous;
      }, required: true);
    } on FileSystemException catch (e, st) {
      quietFailure('engine_updater:revert', e, st);
      return null;
    }
  }

  @override
  int? get cudaMajor {
    final dir = _markedPackDir(rootPath, kind);
    return _manifests[dir]?.manifest.cudaMajor;
  }

  @override
  List<String> get unavailableFiles {
    final value = _readActive(rootPath)?['unavailableFiles'];
    return value is List ? value.whereType<String>().toList() : const [];
  }

  @override
  bool markLoadStarted() => _markLoadStarted(rootPath);

  @override
  void markLoadSucceeded() => _markLoadSucceeded(rootPath);
}

Future<void> _deletePackDirectory(String path) async {
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type == FileSystemEntityType.link) {
    await Link(path).delete();
    return;
  }
  if (type != FileSystemEntityType.directory) {
    throw FileSystemException('Expected a pack directory', path);
  }
  final directory = Directory(path);
  await for (final entry in directory.list(followLinks: false)) {
    if (entry is Directory) {
      await _deletePackDirectory(entry.path);
    } else {
      await entry.delete();
    }
  }
  await directory.delete();
}

Future<bool> _promotePackInWorker({
  required String root,
  required EnginePackKind kind,
  required String pin,
  required String tag,
  required String staging,
  required String target,
  required String quarantine,
  required EnginePackManifest manifest,
  required List<int> manifestBytes,
  required List<int> signature,
  required List<String> unavailableFiles,
}) => Isolate.run(
  () => _withPackLock(root, () {
    final state = _readState(root);
    if (_belowRevisionFloor(root, tag, state, kind, pin)) return false;
    final aside = Directory('$target$_legacySuffix');
    final scheduled = File('$target$deleteOnStartSuffix');
    final promotion = p.basename(quarantine);
    final installed = Directory(target);
    var movedAside = false;
    void discardPromotion() {
      if (movedAside) {
        _restoreLegacy(aside, installed, quarantine);
      } else {
        _quarantinePack(installed, quarantine);
      }
    }

    try {
      // An interrupted restore owns the aside until startup can recover it.
      // A leftover aside of a promotion that finished but could not quarantine
      // its old pack is not an interruption: its marker, or the promotion nonce
      // of the pack it produced, identifies it, so it must not block this
      // activation for the rest of the session.
      if (FileSystemEntity.typeSync(aside.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        final asideMarker = File('${aside.path}$deleteOnStartSuffix');
        final activePromotion = _readActive(root)?['promotion'];
        final asidePromotion = _readPackMetadata(aside.path)?['promotion'];
        final leftover =
            asideMarker.existsSync() ||
            (activePromotion is String && asidePromotion == activePromotion);
        if (!leftover) return false;
        try {
          if (asideMarker.existsSync()) asideMarker.deleteSync();
        } on FileSystemException {
          return false;
        }
        if (!_quarantinePack(aside, _quarantinePath(root, tag))) return false;
      }
      final type = FileSystemEntity.typeSync(target, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        installed.renameSync(aside.path);
        movedAside = true;
      } else if (type != FileSystemEntityType.notFound) {
        return false;
      }
      if (scheduled.existsSync()) scheduled.deleteSync();
      Directory(staging).renameSync(target);
    } on FileSystemException {
      if (movedAside) discardPromotion();
      return false;
    }

    final expected = [
      for (final file in manifest.files)
        <String>[file.name, '${file.size}', file.sha256],
    ];
    if (!_hashPackFolder(target, expected)) {
      try {
        _writeStateLocked(root, state.interrupt(tag), requiredWrite: true);
      } finally {
        discardPromotion();
      }
      return false;
    }
    try {
      // Save the exact signed bytes for subsequent loads.
      File(
        p.join(target, installedManifestName),
      ).writeAsBytesSync(manifestBytes, flush: true);
      File(
        p.join(target, installedSignatureName),
      ).writeAsBytesSync(signature, flush: true);
      File(p.join(target, installedMetaName)).writeAsStringSync(
        jsonEncode({
          'unavailableFiles': unavailableFiles,
          'promotion': promotion,
        }),
        flush: true,
      );
    } on FileSystemException {
      discardPromotion();
      return false;
    }
    try {
      // The active pack and its floor become visible in the same atomic rename.
      _writeActiveLocked(
        root,
        tag,
        target,
        manifest.cudaMajor,
        unavailableFiles,
        verifiedTag: tag,
        promotion: promotion,
      );
    } on FileSystemException {
      discardPromotion();
      rethrow;
    }

    // Keep the floor in state.json too so it survives switching to bundled.
    // The promoted tag passed every check, so its earlier interruption or
    // failure records go with it.
    _writeStateLocked(
      root,
      state.copyWith(
        crashCount: 0,
        revertAcknowledged: state.failedTags.isNotEmpty,
        failedTags: state.failedTags.where((failed) => failed != tag).toList(),
        badTags: state.badTags.where((bad) => bad != tag).toList(),
        interruptedTags: state.interruptedTags
            .where((pending) => pending != tag)
            .toList(),
        clearInFlight: state.inFlightTag == tag,
        clearUnverified: true,
        verifiedTag: tag,
      ),
    );
    if (movedAside && !_quarantinePack(aside, quarantine)) {
      try {
        File(
          '${aside.path}$deleteOnStartSuffix',
        ).writeAsStringSync('', flush: true);
      } on FileSystemException catch (e, st) {
        quietFailure('engine_updater:legacy-schedule', e, st);
      }
    }
    return true;
  }, required: true),
);

/// A failed rename leaves the aside intact for the next startup.
void _restoreLegacy(Directory aside, Directory target, String quarantine) {
  if (!_quarantinePack(target, quarantine)) return;
  try {
    aside.renameSync(target.path);
  } on FileSystemException catch (e, st) {
    quietFailure('engine_updater:restore-legacy', e, st);
  }
}

bool _quarantinePack(Directory directory, String quarantine) {
  try {
    final type = FileSystemEntity.typeSync(directory.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return true;
    if (type != FileSystemEntityType.directory) return false;
    directory.renameSync(quarantine);
    return true;
  } on FileSystemException catch (e, st) {
    quietFailure('engine_updater:quarantine', e, st);
    return false;
  }
}

Future<void> _cleanQuarantine(String path) async {
  try {
    await _deletePackDirectory(path);
  } on FileSystemException catch (e, st) {
    // Startup scans quarantines, including those left by an interrupted run.
    quietFailure('engine_updater:quarantine-cleanup', e, st);
  }
}

String _quarantinePath(String root, String tag) =>
    p.join(root, '$tag$_brokenSuffix.${const Uuid().v4()}');

void _recordInterruptedTag(String root, String tag) {
  _updateState(root, (state) => state.interrupt(tag), requiredWrite: true);
}

/// Resolves an install that was still in flight when the process died. The
/// interruption is recorded durably for the tag before the staging folder is
/// touched, so neither a failed cleanup nor a restart can lose it: the tag is
/// never installed automatically again and only a manual check may retry it.
Future<void> _recoverInFlight(String root, EnginePackKind kind) async {
  final state = _readState(root);
  final tag = state.inFlightTag;
  if (tag == null) return;
  if (kind.parseTag(tag) == null) {
    _updateState(root, (current) => current.copyWith(clearInFlight: true));
    return;
  }
  try {
    final recovered = _updateState(
      root,
      (current) =>
          current.inFlightTag == tag ? current.interrupt(tag) : current,
      requiredWrite: true,
    );
    if (!recovered.interruptedTags.contains(tag)) return;
  } on FileSystemException catch (e, st) {
    // The marker stays, so the next start records the interruption again.
    quietFailure('engine_updater:in-flight-record', e, st);
    return;
  }
  try {
    await _deletePackDirectory(p.join(root, 'staging', tag));
  } on FileSystemException catch (e, st) {
    quietFailure('engine_updater:in-flight-cleanup', e, st);
  }
}

Future<void> _recoverLegacyPacks(String root, EnginePackKind kind) async {
  final directory = Directory(root);
  if (!directory.existsSync()) return;
  final entries = await directory.list(followLinks: false).toList();
  final asides = entries.whereType<Directory>().where(
    (entry) => p.basename(entry.path).endsWith(_legacySuffix),
  );
  if (asides.isEmpty) return;
  try {
    _withPackLock(root, () {
      final active = _readActive(root);
      for (final aside in asides) {
        final name = p.basename(aside.path);
        final tag = name.substring(0, name.length - _legacySuffix.length);
        if (kind.parseTag(tag) == null ||
            FileSystemEntity.typeSync(aside.path, followLinks: false) !=
                FileSystemEntityType.directory ||
            File('${aside.path}$deleteOnStartSuffix').existsSync()) {
          continue;
        }
        final target = Directory(p.join(root, tag));
        final quarantine = _quarantinePath(root, tag);
        final promotion = active?['promotion'];
        if (active?['tag'] == tag &&
            promotion is String &&
            _readPackMetadata(target.path)?['promotion'] == promotion) {
          _quarantinePack(aside, quarantine);
        } else {
          _restoreLegacy(aside, target, quarantine);
        }
      }
    }, required: true);
  } on FileSystemException catch (e, st) {
    quietFailure('engine_updater:recover-legacy', e, st);
  }
}

/// Hashes every file of an installed pack folder against the signed manifest
/// (name, size and SHA-256) inside a worker isolate. The folder may only hold
/// the pack files plus the copied manifest, signature and meta file.
bool _hashPackFolder(String dir, List<List<String>> expected) {
  final wanted = {for (final file in expected) file[0].toLowerCase(): file};
  final seen = <String>{};
  try {
    for (final entity in Directory(dir).listSync(followLinks: false)) {
      if (entity is! File) return false;
      final name = p.basename(entity.path).toLowerCase();
      if (name == installedManifestName ||
          name == installedSignatureName ||
          name == installedMetaName) {
        continue;
      }
      final file = wanted[name];
      if (file == null || !seen.add(name)) return false;
      if (entity.lengthSync() != int.parse(file[1])) return false;
      if (_sha256File(entity).toString() != file[2]) return false;
    }
  } catch (e) {
    // An unreadable folder is an unverified pack, never an exception here.
    return false;
  }
  return seen.length == wanted.length;
}

/// Runs only during startup preparation, before installing any loader hooks.
/// Failed deletions retain their marker and remain excluded from loading.
Future<void> _deleteScheduledPacks(String root, EnginePackKind kind) async {
  final directory = Directory(root);
  if (!await directory.exists()) return;
  const suffix = '.delete-on-start';
  for (final entry in await directory.list(followLinks: false).toList()) {
    final name = p.basename(entry.path);
    final quarantine = _quarantineName.firstMatch(name);
    if (entry is Directory &&
        quarantine != null &&
        (quarantine[1] == 'staging' || kind.parseTag(quarantine[1]) != null)) {
      await _cleanQuarantine(entry.path);
      continue;
    }
    if (entry is! File || !name.endsWith(suffix)) continue;
    final tag = name.substring(0, name.length - suffix.length);
    // `<tag>.legacy` is a legacy install a migration moved aside and
    // `<tag>.broken` a half-promoted folder a failed restore put aside.
    final asideSuffix = tag.endsWith(_legacySuffix)
        ? _legacySuffix
        : tag.endsWith(_brokenSuffix)
        ? _brokenSuffix
        : null;
    final base = asideSuffix == null
        ? tag
        : tag.substring(0, tag.length - asideSuffix.length);
    final owned = tag == 'staging' || kind.ownsFolder(base);
    if (!owned) continue;
    final target = p.normalize(p.absolute(p.join(root, tag)));
    if (!p.isWithin(p.normalize(p.absolute(root)), target)) continue;
    try {
      final aside = _quarantinePath(root, base);
      final moved = _withPackLock(root, () {
        // Activation can clear the deletion marker after the directory scan.
        if (!entry.existsSync() || !_quarantinePack(Directory(target), aside)) {
          return false;
        }
        entry.deleteSync();
        return true;
      }, required: true);
      if (moved) await _cleanQuarantine(aside);
    } on FileSystemException {
      // Retry at the next startup (e.g. another process still maps a DLL).
    }
  }
}

final _quarantineName = RegExp(
  r'^(.+)\.broken\.[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$',
);

/// Resolves the marker to a real pack directory under this engine's root.
String? _markedPackDir(String root, EnginePackKind kind) {
  final marker = _readActive(root);
  final tag = marker?['tag'];
  final dir = marker?['dir'];
  if (tag is! String || dir is! String || kind.parseTag(tag) == null) {
    return null;
  }
  final expected = p.join(root, tag);
  if (!p.equals(p.normalize(dir), expected)) return null;
  if (File(p.join(root, '$tag.delete-on-start')).existsSync()) return null;
  return FileSystemEntity.typeSync(expected, followLinks: false) ==
          FileSystemEntityType.directory
      ? expected
      : null;
}

/// Streaming SHA-256 so a 100 MB bridge does not have to be one Dart buffer.
Digest _sha256File(File file) {
  final output = _DigestSink();
  final sink = sha256.startChunkedConversion(output);
  final input = file.openSync();
  try {
    final buffer = Uint8List(1 << 20);
    while (true) {
      final read = input.readIntoSync(buffer);
      if (read <= 0) break;
      sink.add(
        read == buffer.length ? buffer : Uint8List.sublistView(buffer, 0, read),
      );
    }
  } finally {
    input.closeSync();
  }
  sink.close();
  return output.value!;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// A pack whose DLLs matched its signed manifest at the last [prepare] or at
/// activation. The DLL bytes themselves are re-hashed at every native open.
class _VerifiedPack {
  final Digest manifestHash;
  final Digest signatureHash;
  const _VerifiedPack(this.manifestHash, this.signatureHash);
}

/// One content check of a pack folder and the stat fingerprint it was made
/// with. A later prepare with the same fingerprint reuses [verified] instead
/// of reading every DLL again (P2-2).
class _ContentCheck {
  final String? fingerprint;
  final bool verified;
  const _ContentCheck(this.fingerprint, this.verified);
}

/// GPU variants that failed the install-time smoke test.
List<String> _readPackMeta(String dir) {
  final files = _readPackMetadata(dir)?['unavailableFiles'];
  return files is List ? files.whereType<String>().toList() : const [];
}

Map? _readPackMetadata(String dir) {
  try {
    if (FileSystemEntity.typeSync(dir, followLinks: false) !=
        FileSystemEntityType.directory) {
      return null;
    }
    final file = File(p.join(dir, installedMetaName));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return null;
    }
    final decoded = jsonDecode(file.readAsStringSync());
    return decoded is Map ? decoded : null;
  } catch (_) {
    return null;
  }
}

String? _revisionFloor(
  String root,
  _State state,
  EnginePackKind kind,
  String? pin,
) {
  final markerFloor = _readActive(root)?['verifiedTag'];
  final saved = state.verifiedTag;
  if (markerFloor is! String) return saved;
  if (saved != null &&
      kind.compareTags(saved, markerFloor, pin: pin) > 0 &&
      (kind == EnginePackKind.llamaCpp ||
          kind.sameReleaseFamily(saved, markerFloor, pin: pin))) {
    return saved;
  }
  return markerFloor;
}

bool _belowRevisionFloor(
  String root,
  String tag,
  _State state,
  EnginePackKind kind,
  String? pin,
) {
  final floor = _revisionFloor(root, state, kind, pin);
  return floor != null &&
      (kind == EnginePackKind.llamaCpp ||
          kind.sameReleaseFamily(tag, floor, pin: pin)) &&
      kind.compareTags(tag, floor, pin: pin) < 0;
}

/// True when [tag] is the revision floor itself or older. The automatic check
/// uses it so the pack the user switched away from never comes back by itself
/// (P1); a manual check may still offer it.
bool _notNewerThanFloor(
  String root,
  String tag,
  _State state,
  EnginePackKind kind,
  String? pin,
) {
  final floor = _revisionFloor(root, state, kind, pin);
  return floor != null &&
      (kind == EnginePackKind.llamaCpp ||
          kind.sameReleaseFamily(tag, floor, pin: pin)) &&
      kind.compareTags(tag, floor, pin: pin) <= 0;
}

void _markUnverified(String root, String tag) {
  try {
    _updateState(
      root,
      (state) => state.unverifiedTag == tag
          ? state
          : state.copyWith(unverifiedTag: tag),
    );
  } catch (e, st) {
    quietFailure('engine_updater:mark-unverified', e, st);
  }
}

void _clearUnverified(String root, String tag) {
  try {
    _updateState(
      root,
      (state) => state.unverifiedTag != tag
          ? state
          : state.copyWith(clearUnverified: true),
    );
  } catch (e, st) {
    quietFailure('engine_updater:clear-unverified', e, st);
  }
}

/// Keeps the newest signed install of a release family as the anti-rollback
/// floor, even when the active pack no longer verifies (P2 re-review).
void _noteVerified(String root, String tag, EnginePackKind kind, String pin) {
  try {
    _updateState(root, (state) {
      if (_readActive(root)?['tag'] != tag) return state;
      final floor = state.verifiedTag;
      if (floor == null) return state.copyWith(verifiedTag: tag);
      // llama.cpp builds are one line; ik tags only compare inside one commit,
      // so another pinned commit replaces the floor.
      final sameLine =
          kind == EnginePackKind.llamaCpp ||
          kind.sameReleaseFamily(floor, tag, pin: pin);
      if (sameLine && kind.compareTags(tag, floor, pin: pin) <= 0) {
        return state;
      }
      return state.copyWith(verifiedTag: tag);
    });
  } catch (e, st) {
    quietFailure('engine_updater:note-verified', e, st);
  }
}

bool _markLoadStarted(String root) {
  try {
    _updateState(
      root,
      (state) => state.copyWith(crashCount: state.crashCount + 1),
      requiredWrite: true,
    );
    return true;
  } on FileSystemException catch (e, st) {
    // Without the marker the crash guard cannot notice a crash loop, so the
    // caller refuses the pack for this load instead of running it unguarded.
    quietFailure('engine_updater:markLoadStarted', e, st);
    return false;
  }
}

void _markLoadSucceeded(String root) {
  try {
    _updateState(
      root,
      (state) => state.crashCount == 0 ? state : state.copyWith(crashCount: 0),
    );
  } on FileSystemException catch (e, st) {
    quietFailure('engine_updater:markLoadSucceeded', e, st);
  }
}

/// Last check, automatic update exclusions, the crash guard and the integrity
/// of the installed pack.
class _State {
  final DateTime? lastCheck;

  /// Tags that failed the CPU smoke test and require a manual retry.
  final List<String> badTags;

  /// Packs the crash guard reverted. They stay out of automatic installs until
  /// a manual check reinstalls one (a fixed build may reuse the tag).
  final List<String> failedTags;

  /// Tags whose install was interrupted or failed verification. They stay out
  /// of automatic installs until a manual retry succeeds.
  final List<String> interruptedTags;
  final int crashCount;
  final bool revertAcknowledged;

  /// Tag whose saved manifest no longer verifies; every load refuses it.
  final String? unverifiedTag;

  /// The newest signed install of the release family. Anti-rollback floor:
  /// it outlives a pack that stopped verifying (P2 re-review).
  final String? verifiedTag;

  /// The pack with an installation in progress.
  final String? inFlightTag;
  const _State({
    this.lastCheck,
    this.badTags = const [],
    this.failedTags = const [],
    this.interruptedTags = const [],
    this.crashCount = 0,
    this.revertAcknowledged = false,
    this.unverifiedTag,
    this.verifiedTag,
    this.inFlightTag,
  });

  _State interrupt(String tag) => copyWith(
    interruptedTags: interruptedTags.contains(tag)
        ? interruptedTags
        : [...interruptedTags, tag],
    clearInFlight: inFlightTag == tag,
  );

  _State copyWith({
    DateTime? lastCheck,
    List<String>? badTags,
    List<String>? failedTags,
    List<String>? interruptedTags,
    bool clearFailedTags = false,
    int? crashCount,
    bool? revertAcknowledged,
    String? unverifiedTag,
    bool clearUnverified = false,
    String? failedTag,
    String? verifiedTag,
    String? inFlightTag,
    bool clearInFlight = false,
  }) => _State(
    lastCheck: lastCheck ?? this.lastCheck,
    badTags: badTags ?? this.badTags,
    failedTags: clearFailedTags
        ? const []
        : failedTags ??
              (failedTag == null || this.failedTags.contains(failedTag)
                  ? this.failedTags
                  : [...this.failedTags, failedTag]),
    interruptedTags: interruptedTags ?? this.interruptedTags,
    crashCount: crashCount ?? this.crashCount,
    revertAcknowledged: revertAcknowledged ?? this.revertAcknowledged,
    unverifiedTag: clearUnverified ? null : unverifiedTag ?? this.unverifiedTag,
    verifiedTag: verifiedTag ?? this.verifiedTag,
    inFlightTag: clearInFlight ? null : inFlightTag ?? this.inFlightTag,
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
      failedTags: (decoded['failedTags'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      interruptedTags: (decoded['interruptedTags'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      crashCount: (decoded['crashCount'] as num?)?.toInt() ?? 0,
      revertAcknowledged: decoded['revertAcknowledged'] == true,
      unverifiedTag: decoded['unverifiedTag'] is String
          ? decoded['unverifiedTag'] as String
          : null,
      verifiedTag: decoded['verifiedTag'] is String
          ? decoded['verifiedTag'] as String
          : null,
      inFlightTag: decoded['inFlightTag'] is String
          ? decoded['inFlightTag'] as String
          : null,
    );
  } catch (_) {
    // A damaged state file must not stop the app: the defaults (bundled
    // engine, no bad tags) are always safe.
    return const _State(crashCount: _crashLimit);
  }
}

/// A temp path no other writer can take: the process, this isolate and a
/// counter. state.json and active.json are written from both the model-load
/// isolate (crash guard) and the UI; with one fixed `.tmp` name one isolate
/// could consume the other's file, losing a crash attempt or a failed tag.
String _tempPath(String root, String name) =>
    p.join(root, '$name.$pid.${Isolate.current.hashCode}.${_tempWrites++}.tmp');

int _tempWrites = 0;

/// Runs [body] while holding the engines folder's lock file exclusively, so
/// the crash guard in the model-load isolate and the UI cannot lose each
/// other's state.json or active.json update (P3 re-review). A folder that
/// cannot be locked is still used, because the bundled engine must keep
/// working; [required] makes that failure visible to callers that must not
/// continue without the lock (the crash guard).
T _withPackLock<T>(String root, T Function() body, {bool required = false}) {
  RandomAccessFile? lock;
  try {
    final directory = Directory(root);
    if (!directory.existsSync()) directory.createSync(recursive: true);
    lock = File(p.join(root, _lockFileName)).openSync(mode: FileMode.append);
    lock.lockSync(FileLock.blockingExclusive);
  } on FileSystemException {
    if (lock != null) {
      try {
        lock.closeSync();
      } on FileSystemException {
        // The handle is gone either way.
      }
    }
    if (required) rethrow;
    return body();
  }
  try {
    return body();
  } finally {
    try {
      // Closing the handle releases the lock.
      lock.closeSync();
    } on FileSystemException {
      // The OS releases it with the process; nothing else to do.
    }
  }
}

/// Reads, changes and writes state.json under the pack lock.
_State _updateState(
  String root,
  _State Function(_State) change, {
  bool requiredWrite = false,
}) => _withPackLock(root, () {
  final state = _readState(root);
  final next = change(state);
  // A change that keeps the same state writes nothing.
  if (!identical(state, next)) {
    _writeStateLocked(root, next, requiredWrite: requiredWrite);
  }
  return next;
}, required: requiredWrite);

/// Writes state.json while the caller holds the pack lock.
void _writeStateLocked(
  String root,
  _State state, {
  bool requiredWrite = false,
}) {
  for (var attempt = 0; ; attempt++) {
    try {
      final directory = Directory(root);
      if (!directory.existsSync()) directory.createSync(recursive: true);
      final temp = File(_tempPath(root, 'state.json'));
      temp.writeAsStringSync(
        jsonEncode({
          if (state.lastCheck != null)
            'lastCheck': state.lastCheck!.toUtc().toIso8601String(),
          'badTags': state.badTags,
          'failedTags': state.failedTags,
          'interruptedTags': state.interruptedTags,
          'crashCount': state.crashCount,
          'revertAcknowledged': state.revertAcknowledged,
          if (state.unverifiedTag != null) 'unverifiedTag': state.unverifiedTag,
          if (state.verifiedTag != null) 'verifiedTag': state.verifiedTag,
          if (state.inFlightTag != null) 'inFlightTag': state.inFlightTag,
        }),
        flush: true,
      );
      try {
        temp.renameSync(p.join(root, 'state.json'));
      } on FileSystemException {
        _deleteTemp(temp);
        rethrow;
      }
      return;
    } on FileSystemException {
      // One retry covers a temp file that a previous attempt left behind.
      if (attempt == 0) continue;
      if (requiredWrite) rethrow;
      // A read-only profile keeps the bundled
      // engine instead of failing a model load.
      return;
    }
  }
}

void _deleteTemp(File temp) {
  try {
    if (temp.existsSync()) temp.deleteSync();
  } on FileSystemException {
    // Best effort: a stale temp file is ignored by every reader.
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

/// Atomically replaces active.json while the caller holds the pack lock.
void _writeActiveLocked(
  String root,
  String tag,
  String dir,
  int? cudaMajor,
  List<String> unavailableFiles, {
  String? verifiedTag,
  String? promotion,
}) {
  for (var attempt = 0; ; attempt++) {
    try {
      final directory = Directory(root);
      if (!directory.existsSync()) directory.createSync(recursive: true);
      final temp = File(_tempPath(root, 'active.json'));
      temp.writeAsStringSync(
        jsonEncode({
          'tag': tag,
          'dir': dir,
          'cudaMajor': cudaMajor,
          'unavailableFiles': unavailableFiles,
          'verifiedTag': ?verifiedTag,
          'promotion': ?promotion,
        }),
        flush: true,
      );
      try {
        temp.renameSync(p.join(root, 'active.json'));
      } on FileSystemException {
        _deleteTemp(temp);
        rethrow;
      }
      return;
    } on FileSystemException {
      if (attempt == 0) continue;
      rethrow;
    }
  }
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

/// Hashes every DLL of [dir] against [manifest] in a worker isolate, so a
/// large bridge is never read on the calling (UI) isolate. Runs before a
/// load, after a staged pack is promoted and when a pack is prepared.
Future<bool> verifyPackContent(String dir, EnginePackManifest manifest) async {
  final expected = [
    for (final file in manifest.files)
      <String>[file.name, '${file.size}', file.sha256],
  ];
  try {
    return await Isolate.run(() => _hashPackFolder(dir, expected));
  } catch (e, st) {
    quietFailure('engine_updater:verify-pack', e, st);
    return false;
  }
}
