import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_pack.dart';
import 'engine_updater.dart';
import '../../core/island/status_island.dart';
import '../../core/l10n/l10n.dart';
import '../../inference/engine/engine_descriptor.dart';
import '../../inference/engine/engine_registry_provider.dart';

final _log = Logger('EngineUpdates');

/// The one updater of the app run. main() prepares it before the first
/// model load, so a downloaded engine is already used by that load.
final engineUpdater = EngineUpdater();

/// The optional ik_llama.cpp pack, in its own folder under the engines root.
/// It is never installed automatically: the user chooses that engine per
/// model, and only an installed pack makes it available.
final ikEngineUpdater = EngineUpdater(kind: EnginePackKind.ikLlama);

/// Overridable in tests with an updater that has fake fetch and root.
final engineUpdaterProvider = Provider<EngineUpdater>((_) => engineUpdater);
final ikEngineUpdaterProvider = Provider<EngineUpdater>((_) => ikEngineUpdater);

/// Installs the loader hooks for every engine kind before the first model
/// load. A pack folder that cannot be read leaves that engine unavailable
/// rather than failing startup.
Future<void> prepareEngineUpdaters() async {
  await engineUpdater.prepare();
  try {
    await ikEngineUpdater.prepare();
  } catch (e) {
    _log.warning('The ik_llama.cpp pack folder is unreadable', e);
  }
}

enum EngineUpdatePhase {
  idle,
  checking,
  upToDate,
  available,
  downloading,
  ready,
  offline,
  error,
}

class EngineUpdateView {
  final EngineUpdatePhase phase;

  /// The pack in use (`engine-b12503`), or null for the bundled engine.
  final String? installed;

  /// The newer pack found by the last check.
  final String? latest;
  final int received, total;

  /// Why the last check or install failed; the panel localizes it. Raw
  /// exception detail stays in the log (release review P2 l10n).
  final EngineUpdateProblem? problem;
  final DateTime? lastCheck;
  final bool autoCheck;

  /// Two loads from the pack failed and the app went back to the bundled one.
  final bool reverted;

  /// The installed pack's manifest or DLLs no longer verify (or predate the
  /// copied manifest), so the app runs the bundled engine until it is
  /// reinstalled. Shown as a notice, never swapped silently.
  final bool unverified;

  /// The verified ik_llama.cpp pack tag, or null when its engine is not
  /// installed. The Settings row watches this instead of its own copy.
  final String? ikInstalled;

  /// The installed ik_llama.cpp pack no longer verifies.
  final bool ikUnverified;

  /// A pack folder (active, reverted, unverified or awaiting deletion) is
  /// still on disk. The panel keeps its removal row visible from this alone,
  /// whatever the revert notice says.
  final bool packsOnDisk;

  const EngineUpdateView({
    this.phase = EngineUpdatePhase.idle,
    this.installed,
    this.latest,
    this.received = 0,
    this.total = 0,
    this.problem,
    this.lastCheck,
    this.autoCheck = true,
    this.reverted = false,
    this.unverified = false,
    this.ikInstalled,
    this.ikUnverified = false,
    this.packsOnDisk = false,
  });

  bool get busy =>
      phase == EngineUpdatePhase.checking ||
      phase == EngineUpdatePhase.downloading;

  EngineUpdateView copyWith({
    EngineUpdatePhase? phase,
    String? installed,
    bool clearInstalled = false,
    String? latest,
    int? received,
    int? total,
    EngineUpdateProblem? problem,
    bool clearProblem = false,
    DateTime? lastCheck,
    bool? autoCheck,
    bool? reverted,
    bool? unverified,
    String? ikInstalled,
    bool clearIkInstalled = false,
    bool? ikUnverified,
    bool? packsOnDisk,
  }) => EngineUpdateView(
    phase: phase ?? this.phase,
    installed: clearInstalled ? null : installed ?? this.installed,
    latest: latest ?? this.latest,
    received: received ?? this.received,
    total: total ?? this.total,
    problem: clearProblem ? null : problem ?? this.problem,
    lastCheck: lastCheck ?? this.lastCheck,
    autoCheck: autoCheck ?? this.autoCheck,
    reverted: reverted ?? this.reverted,
    unverified: unverified ?? this.unverified,
    ikInstalled: clearIkInstalled ? null : ikInstalled ?? this.ikInstalled,
    ikUnverified: ikUnverified ?? this.ikUnverified,
    packsOnDisk: packsOnDisk ?? this.packsOnDisk,
  );
}

const _autoKey = 'engine_auto_update';

/// Check, download, verify and install engine packs (Windows). The automatic
/// path runs at most once a day and installs without asking; the change
/// applies on the next model load, never to a running model.
class EngineUpdateController extends Notifier<EngineUpdateView> {
  bool _started = false;

  @override
  EngineUpdateView build() => const EngineUpdateView();

  EngineUpdater get _updater => ref.read(engineUpdaterProvider);
  EngineUpdater get _ik => ref.read(ikEngineUpdaterProvider);

  /// Called once after the desktop shell is up.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    var auto = true;
    try {
      auto = (await SharedPreferences.getInstance()).getBool(_autoKey) ?? true;
    } catch (_) {}
    await _refreshInstalled(autoCheck: auto);
    if (!ref.mounted) return;
    if (!auto) return;
    // A pack installed by an earlier build has no copied manifest (P2-2).
    // Re-offer its tag at startup instead of quietly running the bundled
    // engine; the old folder stays until the signed reinstall succeeds. This
    // bypasses the daily interval but is not a manual request: a tag an
    // earlier interruption excluded is never installed by it (P2).
    if (_updater.needsMigration) {
      _log.info('Re-offering the installed engine pack for a signed reinstall');
      await _check(install: true, ignoreInterval: true);
      return;
    }
    await _check(install: true);
  }

  Future<void> setAutoCheck(bool value) async {
    state = state.copyWith(autoCheck: value);
    try {
      await (await SharedPreferences.getInstance()).setBool(_autoKey, value);
    } catch (e) {
      _log.fine('Could not save the engine update switch', e);
    }
  }

  /// The user's own check: it ignores the interval and is the only path that
  /// may retry a tag an earlier interruption excluded.
  Future<void> checkNow() => _check(manual: true);

  /// Optional ik_llama.cpp engine pack: check GitHub and, when [install] is
  /// true, download, verify, smoke test and activate it. It is never installed
  /// automatically, and it never replaces the llama.cpp default: the engine is
  /// used only for models the user assigns to it. Returns the failure instead
  /// of swallowing it, so the Settings row can show what went wrong.
  Future<EngineCheckResult> checkIkEnginePack({bool install = false}) async {
    if (!ref.read(ikEngineAvailableProvider)) {
      return const EngineCheckResult(
        EngineCheckState.error,
        problem: EngineUpdateProblem.noPinnedBuild,
      );
    }
    final EngineCheckResult result;
    try {
      result = await _ik.check(manual: true);
    } catch (e) {
      _log.info('ik_llama.cpp pack check failed: $e');
      return const EngineCheckResult(
        EngineCheckState.error,
        problem: EngineUpdateProblem.checkFailed,
      );
    }
    if (install) {
      if (result.state != EngineCheckState.available) {
        await _refreshInstalled();
        return result;
      }
      try {
        final download = await _ik.download();
        if (download.state != EngineDownloadState.done) {
          await _refreshInstalled();
          return EngineCheckResult(
            EngineCheckState.error,
            problem: download.problem ?? EngineUpdateProblem.downloadFailed,
            message: download.message,
          );
        }
        if (!await _ik.activate()) {
          await _refreshInstalled();
          return const EngineCheckResult(
            EngineCheckState.error,
            problem: EngineUpdateProblem.installFailed,
          );
        }
      } catch (e) {
        _log.info('ik_llama.cpp pack install failed: $e');
        await _refreshInstalled();
        return const EngineCheckResult(
          EngineCheckState.error,
          problem: EngineUpdateProblem.installFailed,
        );
      }
    }
    await _refreshInstalled();
    return result;
  }

  /// Called after a failed ik_llama.cpp load. The crash guard may have
  /// reverted the pack, so the installed set is re-read: the registry must
  /// stop offering an engine whose DLLs can no longer be opened.
  Future<void> noteIkLoadFailure() async {
    await _refreshInstalled();
    if (!ref.mounted) return;
    if (_ik.revertedNotice) {
      ref
          .read(islandProvider.notifier)
          .toast(appStrings.ikEnginePackReverted, tone: IslandTone.warning);
      // Acknowledging stops the same notice on every further load; the crash
      // guard keeps that release out of automatic installs.
      _ik.acknowledgeRevert();
    }
  }

  /// Downloads and installs the pack the last check found.
  Future<void> update() async {
    if (state.busy || state.phase != EngineUpdatePhase.available) return;
    await _install();
  }

  Future<void> useBundled() async {
    if (state.busy) return;
    _log.info('Reverting to the built-in engine');
    try {
      await _updater.useBundled();
      await _refreshInstalled();
      if (!ref.mounted) return;
      state = state.copyWith(phase: EngineUpdatePhase.idle, clearProblem: true);
    } catch (e) {
      // A read-only engines folder makes the marker deletion fail; the panel
      // must say so instead of the press doing nothing.
      _log.info('Reverting to the built-in engine failed: $e');
      await _refreshInstalled();
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: EngineUpdatePhase.error,
        problem: EngineUpdateProblem.useBundledFailed,
      );
    }
  }

  Future<void> removeAll() async {
    if (state.busy) return;
    _log.info('Removing engine packs; selecting built-in');
    try {
      await _updater.removeAll();
      // The optional ik_llama.cpp pack is a downloaded engine too.
      try {
        await _ik.removeAll();
      } catch (e) {
        _log.fine('ik_llama.cpp pack removal failed', e);
      }
      await _refreshInstalled();
      if (!ref.mounted) return;
      state = state.copyWith(phase: EngineUpdatePhase.idle, clearProblem: true);
      _log.info('Engine pack removal scheduled for next startup');
    } catch (e) {
      _log.info('Engine pack removal failed: $e');
      await _refreshInstalled();
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: EngineUpdatePhase.error,
        problem: EngineUpdateProblem.removeFailed,
      );
    }
  }

  void acknowledgeRevert() {
    _updater.acknowledgeRevert();
    // The optional ik pack has its own crash guard and notice.
    _ik.acknowledgeRevert();
    state = state.copyWith(reverted: false);
  }

  Future<void> _check({
    bool manual = false,
    bool install = false,
    bool ignoreInterval = false,
  }) async {
    if (state.busy) return;
    state = state.copyWith(
      phase: EngineUpdatePhase.checking,
      clearProblem: true,
    );
    final EngineCheckResult result;
    try {
      result = await _updater.check(
        manual: manual,
        ignoreInterval: ignoreInterval,
      );
    } catch (e) {
      _log.info('Engine update check: error ($e)');
      state = state.copyWith(
        phase: EngineUpdatePhase.error,
        problem: EngineUpdateProblem.checkFailed,
      );
      return;
    }
    _log.info(switch (result.state) {
      EngineCheckState.upToDate => 'Engine update check: up to date',
      EngineCheckState.available =>
        'Engine update check: available ${result.tag}',
      EngineCheckState.offline =>
        'Engine update check: offline (${result.message})',
      EngineCheckState.error =>
        'Engine update check: error (${result.message})',
    });
    if (!ref.mounted) return;
    state = state.copyWith(
      lastCheck: result.lastCheck?.toLocal(),
      phase: switch (result.state) {
        EngineCheckState.upToDate => EngineUpdatePhase.upToDate,
        EngineCheckState.available => EngineUpdatePhase.available,
        EngineCheckState.offline => EngineUpdatePhase.offline,
        EngineCheckState.error => EngineUpdatePhase.error,
      },
      latest: result.tag,
      total: result.size ?? 0,
      problem: result.problem,
    );
    if (install && result.state == EngineCheckState.available) {
      await _install();
    }
  }

  Future<void> _install() async {
    state = state.copyWith(
      phase: EngineUpdatePhase.downloading,
      received: 0,
      clearProblem: true,
    );
    _log.info('Engine download started: ${state.latest}');
    try {
      final result = await _updater.download(
        onProgress: (received, total) {
          if (ref.mounted) {
            state = state.copyWith(received: received, total: total);
          }
        },
      );
      _log.info(
        'Engine download finished: ${result.state.name} ${result.message ?? ''}',
      );
      if (!ref.mounted) return;
      if (result.state != EngineDownloadState.done) {
        state = state.copyWith(
          phase: result.state == EngineDownloadState.cancelled
              ? EngineUpdatePhase.available
              : EngineUpdatePhase.error,
          problem: result.state == EngineDownloadState.cancelled
              ? null
              : result.problem ?? EngineUpdateProblem.downloadFailed,
        );
        return;
      }
      _log.info('Installing engine pack: ${state.latest}');
      final activated = await _updater.activate();
      if (!ref.mounted) return;
      _log.info(
        'Engine installation ${activated ? 'finished' : 'failed'}: ${state.latest}',
      );
      await _refreshInstalled();
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: activated ? EngineUpdatePhase.ready : EngineUpdatePhase.error,
        problem: activated ? null : EngineUpdateProblem.installFailed,
      );
    } catch (e) {
      // A failed install (read-only or full engines folder) must not leave the
      // phase at "downloading": busy would stay true and disable every button
      // for the rest of the session.
      _log.info('Engine installation failed: $e');
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: EngineUpdatePhase.error,
        problem: EngineUpdateProblem.installFailed,
      );
      await _refreshInstalled();
    }
  }

  Future<void> _refreshInstalled({bool? autoCheck}) async {
    String? llamaDir;
    String? ikDir;
    var unverified = false;
    var ikUnverified = false;
    var packsOnDisk = false;
    try {
      await _updater.prepare();
      // One lookup per refresh, and it is the verified one: the marker alone
      // can point at a pack whose manifest no longer verifies (P2-3).
      llamaDir = _updater.verifiedPackDir();
      unverified = _updater.unverifiedNotice;
      // Rows that act on the folders must not depend on the marker or on the
      // revert notice: a reverted, unverified or already released pack still
      // occupies hundreds of MB until it is removed (P2).
      packsOnDisk = await _updater.packFilesOnDisk();
    } catch (e) {
      _log.fine('Engine packs unreadable', e);
    }
    try {
      await _ik.prepare();
      ikDir = _ik.verifiedPackDir();
      ikUnverified = _ik.unverifiedNotice;
      unverified = unverified || ikUnverified;
      packsOnDisk = packsOnDisk || await _ik.packFilesOnDisk();
    } catch (e) {
      // A read-only or missing folder keeps ik_llama.cpp unavailable; the
      // llama.cpp engine and the panel are unaffected.
      _log.fine('ik_llama.cpp pack folder unreadable', e);
    }
    // The registry offers an optional engine only while its pack is really
    // installed, verified and its active marker survived the crash guard.
    try {
      ref.read(installedEnginePacksProvider.notifier).state = {
        if (llamaDir != null) llamaCppEngineId,
        if (ikDir != null) ikLlamaEngineId,
      };
    } catch (e) {
      _log.fine('Could not publish installed engine packs', e);
    }
    // The prepare above awaits disk: the screen may have closed meanwhile.
    if (!ref.mounted) return;
    if (_updater.revertedNotice && !state.reverted) {
      _log.info('Engine pack reverted to built-in after failed model loads');
    }
    final tag = llamaDir == null ? null : p.basename(llamaDir);
    final ikTag = ikDir == null ? null : p.basename(ikDir);
    state = state.copyWith(
      installed: tag,
      clearInstalled: tag == null,
      autoCheck: autoCheck,
      lastCheck: _updater.lastCheck?.toLocal(),
      reverted: _updater.revertedNotice,
      unverified: unverified,
      ikInstalled: ikTag,
      clearIkInstalled: ikTag == null,
      ikUnverified: ikUnverified,
      packsOnDisk: packsOnDisk,
    );
  }
}

final engineUpdateProvider =
    NotifierProvider<EngineUpdateController, EngineUpdateView>(
      EngineUpdateController.new,
    );
