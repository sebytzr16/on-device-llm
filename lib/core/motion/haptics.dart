import 'package:flutter/services.dart';

/// The few moments that vibrate (the chosen design: subtle, key moments only).
/// Nothing fires while scrolling or streaming, and nothing at Motion Off.
abstract final class AppHaptics {
  /// Follows the Motion setting; the app sets it with the motion level.
  static bool enabled = true;

  /// A choice changed: a pill cycled, a toggle flipped, a sheet opened, a
  /// step snapped, something copied.
  static void tick() {
    if (enabled) HapticFeedback.selectionClick();
  }

  /// A message sent, a reply stopped, a long-press menu opened.
  static void press() {
    if (enabled) HapticFeedback.lightImpact();
  }

  /// Something finished well: the answer is done, a model is ready.
  static void success() {
    if (enabled) HapticFeedback.mediumImpact();
  }
}
