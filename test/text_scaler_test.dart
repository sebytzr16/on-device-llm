import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/design/text_scaler.dart';

/// A test TextScaler that applies a simple nonlinear scaling.
class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();

  @override
  double get textScaleFactor => 1.3;

  @override
  double scale(double fontSize) {
    // Simulate a nonlinear accessibility scaler: small fonts scale more,
    // large fonts scale less.
    if (fontSize < 14) return fontSize * 1.5;
    if (fontSize < 24) return fontSize * 1.3;
    return fontSize * 1.1;
  }
}

void main() {
  group('ComposedTextScaler', () {
    test('composes base scaler with multiplier', () {
      const base = TextScaler.linear(1.2);
      const composed = ComposedTextScaler(base, 1.5);
      expect(composed.scale(10), 18.0); // 10 * 1.2 * 1.5
      expect(composed.scale(20), 36.0); // 20 * 1.2 * 1.5
    });

    test('preserves nonlinear base scaler behavior', () {
      const base = _NonlinearScaler();
      const composed = ComposedTextScaler(base, 2.0);
      // The preference enlarges the size first, then the platform curve
      // applies to the enlarged size (no double scaling of large text).
      // 10 * 2.0 = 20 -> 20 * 1.3 = 26
      expect(composed.scale(10), closeTo(26.0, 1e-9));
      // 18 * 2.0 = 36 -> 36 * 1.1 = 39.6
      expect(composed.scale(18), closeTo(39.6, 1e-9));
      // 30 * 2.0 = 60 -> 60 * 1.1 = 66
      expect(composed.scale(30), closeTo(66.0, 1e-9));
    });

    test('identity multiplier returns base scaler values', () {
      const base = TextScaler.linear(1.3);
      const composed = ComposedTextScaler(base, 1.0);
      expect(composed.scale(10), 13.0);
      expect(composed.scale(20), 26.0);
    });

    test('zero multiplier returns zero', () {
      const base = TextScaler.linear(1.5);
      const composed = ComposedTextScaler(base, 0.0);
      expect(composed.scale(10), 0.0);
    });

    test('works with system TextScaler.noScaling', () {
      const composed = ComposedTextScaler(TextScaler.noScaling, 1.5);
      expect(composed.scale(10), 15.0);
    });
  });
}
