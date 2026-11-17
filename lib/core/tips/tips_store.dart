import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kEnabled = 'tips_enabled_v1';
const _kSeen = 'tips_seen_v1';

/// Stable identifiers for all one-time UI tips.
abstract final class TipIds {
  static const modelsDiscover = 'models.discover';
  static const modelsBestFit = 'models.bestFit';
  static const chatGetModel = 'chat.getModel';
  static const downloadReady = 'download.ready';
  static const optimizeOffer = 'optimize.offer';
  static const chatTourTools = 'chat.tour.tools';
  static const chatTourWeb = 'chat.tour.web';
  static const chatTourThink = 'chat.tour.think';
  static const chatTourAttach = 'chat.tour.attach';
  static const chatTourSlash = 'chat.tour.slash';

  /// Ordered list of the chat tour tips for sequential display.
  static const List<String> chatTour = [
    chatTourTools,
    chatTourWeb,
    chatTourThink,
    chatTourAttach,
    chatTourSlash,
  ];

  /// The phone has no Tools pill (tools sit under "+"), so its tour skips it.
  static const List<String> chatTourMobile = [
    chatTourWeb,
    chatTourThink,
    chatTourAttach,
    chatTourSlash,
  ];
}

/// Immutable state for the tips system.
class TipsState {
  final bool enabled;
  final Set<String> seen;
  final String? showing;

  const TipsState({this.enabled = true, this.seen = const {}, this.showing});

  static const _keep = Object();

  /// [showing] may be set to null; leaving it out keeps the current one.
  TipsState copyWith({
    bool? enabled,
    Set<String>? seen,
    Object? showing = _keep,
  }) {
    return TipsState(
      enabled: enabled ?? this.enabled,
      seen: seen ?? this.seen,
      showing: identical(showing, _keep) ? this.showing : showing as String?,
    );
  }

  /// Returns true if the tip [id] should be shown right now.
  bool shouldShow(String id) =>
      enabled && !seen.contains(id) && (showing == null || showing == id);
}

/// Notifier managing tip visibility and persistence.
class TipsNotifier extends Notifier<TipsState> {
  final _loaded = Completer<void>();

  /// Widget tests of other screens run with tips off, so a bubble never
  /// covers what they tap; tip tests turn this on.
  @visibleForTesting
  static bool showInTests = false;

  static bool get _underTest =>
      !showInTests && Platform.environment.containsKey('FLUTTER_TEST');

  @override
  TipsState build() {
    // Kick off async load; state starts as defaults.
    _load();
    return TipsState(enabled: !_underTest);
  }

  /// Completes when the initial load from SharedPreferences has finished.
  Future<void> get loaded => _loaded.future;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_kEnabled) ?? true;
      final seenList = prefs.getStringList(_kSeen) ?? <String>[];
      // Merged, not replaced: a tip dismissed before the load finished
      // stays dismissed.
      state = state.copyWith(
        enabled: enabled && !_underTest && state.enabled,
        seen: {...seenList, ...state.seen},
      );
    } catch (_) {
      // Ignore load failures; keep defaults.
    } finally {
      if (!_loaded.isCompleted) _loaded.complete();
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, state.enabled);
      await prefs.setStringList(_kSeen, state.seen.toList());
    } catch (_) {
      // Persistence failures are ignored; state still updates.
    }
  }

  /// Claims [id] for display. Returns true if the tip should be shown.
  /// Nothing is claimed before the saved state is read, so a tip already
  /// seen never flashes on start.
  bool claim(String id) {
    if (_loaded.isCompleted && state.shouldShow(id)) {
      state = state.copyWith(showing: id);
      return true;
    }
    return false;
  }

  /// Gives the slot back without marking [id] seen (its page closed).
  void release(String id) {
    if (state.showing == id) state = state.copyWith(showing: null);
  }

  /// Marks [id] as seen and clears [showing] if it matches.
  Future<void> dismiss(String id) async {
    state = state.copyWith(
      seen: {...state.seen, id},
      showing: state.showing == id ? null : state.showing,
    );
    await _persist();
  }

  /// Marks multiple [ids] as seen and clears [showing] if it matches any.
  Future<void> dismissAll(Iterable<String> ids) async {
    final newSeen = {...state.seen, ...ids};
    final newShowing = ids.contains(state.showing) ? null : state.showing;
    state = state.copyWith(seen: newSeen, showing: newShowing);
    await _persist();
  }

  /// Enables or disables the entire tips system.
  Future<void> setEnabled(bool v) async {
    state = state.copyWith(enabled: v, showing: v ? state.showing : null);
    await _persist();
  }

  /// Resets all tips to their initial state (enabled, nothing seen).
  Future<void> resetAll() async {
    state = const TipsState();
    await _persist();
  }

  /// Returns the first id in [ids] that has not been seen, or null if none
  /// or if tips are disabled.
  String? nextIn(List<String> ids) {
    if (!state.enabled) return null;
    for (final id in ids) {
      if (!state.seen.contains(id)) return id;
    }
    return null;
  }
}

final tipsProvider = NotifierProvider<TipsNotifier, TipsState>(
  TipsNotifier.new,
);
