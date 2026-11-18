import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'engine_updater.dart';

final _log = Logger('EngineUpdates');

/// The one updater of the app run. main() prepares it before the first
/// model load, so a downloaded engine is already used by that load.
final engineUpdater = EngineUpdater();

/// Overridable in tests with an updater that has fake fetch and root.
final engineUpdaterProvider = Provider<EngineUpdater>((_) => engineUpdater);

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
  final String? message;
  final DateTime? lastCheck;
  final bool autoCheck;

  /// Two loads from the pack failed and the app went back to the bundled one.
  final bool reverted;

  const EngineUpdateView({
    this.phase = EngineUpdatePhase.idle,
    this.installed,
    this.latest,
    this.received = 0,
    this.total = 0,
    this.message,
    this.lastCheck,
    this.autoCheck = true,
    this.reverted = false,
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
    String? message,
    bool clearMessage = false,
    DateTime? lastCheck,
    bool? autoCheck,
    bool? reverted,
  }) => EngineUpdateView(
    phase: phase ?? this.phase,
    installed: clearInstalled ? null : installed ?? this.installed,
    latest: latest ?? this.latest,
    received: received ?? this.received,
    total: total ?? this.total,
    message: clearMessage ? null : message ?? this.message,
    lastCheck: lastCheck ?? this.lastCheck,
    autoCheck: autoCheck ?? this.autoCheck,
    reverted: reverted ?? this.reverted,
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

  /// Called once after the desktop shell is up.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    var auto = true;
    try {
      auto = (await SharedPreferences.getInstance()).getBool(_autoKey) ?? true;
    } catch (_) {}
    await _refreshInstalled(autoCheck: auto);
    if (auto) await _check(force: false, install: true);
  }

  Future<void> setAutoCheck(bool value) async {
    state = state.copyWith(autoCheck: value);
    try {
      await (await SharedPreferences.getInstance()).setBool(_autoKey, value);
    } catch (e) {
      _log.fine('Could not save the engine update switch', e);
    }
  }

  Future<void> checkNow() => _check(force: true, install: false);

  /// Downloads and installs the pack the last check found.
  Future<void> update() async {
    if (state.busy || state.phase != EngineUpdatePhase.available) return;
    await _install();
  }

  Future<void> useBundled() async {
    if (state.busy) return;
    _log.info('Reverting to the built-in engine');
    await _updater.useBundled();
    await _refreshInstalled();
    state = state.copyWith(phase: EngineUpdatePhase.idle, clearMessage: true);
  }

  Future<void> removeAll() async {
    if (state.busy) return;
    _log.info('Removing engine packs; selecting built-in');
    try {
      await _updater.removeAll();
      await _refreshInstalled();
      state = state.copyWith(phase: EngineUpdatePhase.idle, clearMessage: true);
      _log.info('Engine pack removal scheduled for next startup');
    } catch (e) {
      _log.info('Engine pack removal failed: $e');
      await _refreshInstalled();
      state = state.copyWith(phase: EngineUpdatePhase.error, message: '$e');
    }
  }

  void acknowledgeRevert() {
    _updater.acknowledgeRevert();
    state = state.copyWith(reverted: false);
  }

  Future<void> _check({required bool force, required bool install}) async {
    if (state.busy) return;
    state = state.copyWith(
      phase: EngineUpdatePhase.checking,
      clearMessage: true,
    );
    final EngineCheckResult result;
    try {
      result = await _updater.check(force: force);
    } catch (e) {
      _log.info('Engine update check: error ($e)');
      state = state.copyWith(phase: EngineUpdatePhase.error, message: '$e');
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
      message: result.message,
    );
    if (install && result.state == EngineCheckState.available) {
      await _install();
    }
  }

  Future<void> _install() async {
    state = state.copyWith(
      phase: EngineUpdatePhase.downloading,
      received: 0,
      clearMessage: true,
    );
    _log.info('Engine download started: ${state.latest}');
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
        message: result.message,
      );
      return;
    }
    _log.info('Installing engine pack: ${state.latest}');
    final activated = await _updater.activate();
    _log.info(
      'Engine installation ${activated ? 'finished' : 'failed'}: ${state.latest}',
    );
    await _refreshInstalled();
    state = state.copyWith(
      phase: activated ? EngineUpdatePhase.ready : EngineUpdatePhase.error,
      message: activated ? null : 'The engine pack could not be installed.',
    );
  }

  Future<void> _refreshInstalled({bool? autoCheck}) async {
    String? tag;
    try {
      await _updater.prepare();
      final dir = _updater.activePackDir();
      if (dir != null) tag = p.basename(dir);
    } catch (e) {
      _log.fine('Engine packs unreadable', e);
    }
    if (_updater.revertedNotice && !state.reverted) {
      _log.info('Engine pack reverted to built-in after failed model loads');
    }
    state = state.copyWith(
      installed: tag,
      clearInstalled: tag == null,
      autoCheck: autoCheck,
      lastCheck: _updater.lastCheck?.toLocal(),
      reverted: _updater.revertedNotice,
    );
  }
}

final engineUpdateProvider =
    NotifierProvider<EngineUpdateController, EngineUpdateView>(
      EngineUpdateController.new,
    );
