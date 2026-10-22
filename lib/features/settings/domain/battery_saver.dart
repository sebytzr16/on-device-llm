import 'dart:math';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/device_info.dart';
import 'entities/inference_settings.dart';

/// Settings > Battery saver: when the battery is low (and not charging) or
/// the phone reports severe heat, a local turn runs lighter — no thinking,
/// a shorter answer, fewer pages read and fewer passages to prefill. Nothing
/// that forces a model reload (threads, context, GPU layers) is touched, so
/// switching in and out costs nothing. Remote turns are not affected.
class BatterySaver {
  static const maxTokens = 512;
  static const maxPages = 3;
  static const maxPassages = 6;

  /// Android's "severe" thermal status.
  static const thermalLimit = 3;

  /// Why the saver applies to this turn ("battery 18%", "phone hot:
  /// severe"), or null when it does not.
  static String? reason(InferenceSettings s, DevicePower? power) {
    if (!s.batterySaver || s.usesRemote || power == null) return null;
    if (power.thermalStatus >= thermalLimit) {
      return 'phone hot: ${power.thermalLabel}';
    }
    if (!power.charging &&
        power.level >= 0 &&
        power.level < s.batterySaverLevel) {
      return 'battery ${power.level}%';
    }
    return null;
  }

  /// [s] made lighter; values already below the caps stay as they are.
  static InferenceSettings apply(InferenceSettings s) => s.copyWith(
    thinkingModeEnabled: false,
    maxTokens: min(s.maxTokens, maxTokens),
    maxPagesRead: min(s.maxPagesRead, maxPages),
    evidencePassages: min(s.evidencePassages, maxPassages),
  );

  /// The chat notice for [reason] (from [reason]), in [t]'s language.
  static String notice(String reason, [AppLocalizations? t]) {
    t ??= AppLocalizationsEn();
    final battery = RegExp(r'^battery (\d+)%$').firstMatch(reason);
    final local = battery != null
        ? t.saverReasonBattery(int.parse(battery.group(1)!))
        : reason.startsWith('phone hot: ')
        ? t.saverReasonHot(reason.substring('phone hot: '.length))
        : reason;
    return t.noticeBatterySaver(local, maxTokens);
  }
}
