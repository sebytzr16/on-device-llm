import 'package:flutter/widgets.dart';

/// A [TextScaler] that composes a base scaler with a constant multiplier.
/// This preserves the platform's nonlinear accessibility scaling behavior
/// while applying the user's text size preference.
class ComposedTextScaler extends TextScaler {
  final TextScaler _base;
  final double _multiplier;

  const ComposedTextScaler(this._base, this._multiplier);

  @override
  double scale(double fontSize) {
    return _base.scale(fontSize * _multiplier);
  }

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => _base.textScaleFactor * _multiplier;
}
