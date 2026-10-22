import 'package:flutter/widgets.dart';

import 'motion.dart';

/// Text whose digits roll like an odometer when it changes (tok/s, a
/// percentage, a count); other characters crossfade. Digits roll up when
/// the number grows and down when it shrinks.
class RollingText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Digits roll up from 0 when the text first appears (a fresh result).
  final bool rollIn;
  const RollingText(this.text, {super.key, this.style, this.rollIn = false});

  @override
  State<RollingText> createState() => _RollingTextState();
}

class _RollingTextState extends State<RollingText> {
  bool _up = true;

  static double? _number(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.\-]'), ''));

  @override
  void didUpdateWidget(covariant RollingText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      final before = _number(old.text), after = _number(widget.text);
      if (before != null && after != null && before != after) {
        _up = after > before;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style
        .merge(widget.style)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final chars = widget.text.characters.toList();
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Keyed from the right so units stay put when a digit is added.
          for (var i = 0; i < chars.length; i++)
            KeyedSubtree(
              key: ValueKey(chars.length - i),
              child: _isDigit(chars[i])
                  ? _RollingDigit(
                      digit: chars[i].codeUnitAt(0) - 48,
                      up: _up,
                      rollIn: widget.rollIn,
                      style: style,
                    )
                  : BlurSwitcher(
                      child: Text(
                        chars[i],
                        key: ValueKey(chars[i]),
                        style: style,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  static bool _isDigit(String c) =>
      c.length == 1 && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
}

class _RollingDigit extends StatefulWidget {
  final int digit;
  final bool up, rollIn;
  final TextStyle style;
  const _RollingDigit({
    required this.digit,
    required this.up,
    required this.rollIn,
    required this.style,
  });

  @override
  State<_RollingDigit> createState() => _RollingDigitState();
}

class _RollingDigitState extends State<_RollingDigit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _value = AnimationController.unbounded(
    vsync: this,
    value: widget.rollIn ? 0 : widget.digit.toDouble(),
  );
  bool _rolledIn = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rolledIn || !widget.rollIn) return;
    _rolledIn = true;
    final motion = context.motion;
    _value.springTo(
      widget.digit.toDouble(),
      motion.spring,
      animate: motion.animates,
    );
  }

  @override
  void didUpdateWidget(covariant _RollingDigit old) {
    super.didUpdateWidget(old);
    if (old.digit == widget.digit) return;
    // The nearest position showing the new digit in the rolling direction,
    // so 9 -> 0 goes forward through the top instead of back through 8…1.
    final current = _value.value;
    var target = widget.digit.toDouble();
    if (widget.up) {
      while (target < current - 0.5) {
        target += 10;
      }
      while (target > current + 9.5) {
        target -= 10;
      }
    } else {
      while (target > current + 0.5) {
        target -= 10;
      }
      while (target < current - 9.5) {
        target += 10;
      }
    }
    final motion = context.motion;
    _value.springTo(target, motion.spring, animate: motion.animates);
  }

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: '0', style: widget.style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width, height = painter.height;
    painter.dispose();
    return SizedBox(
      width: width,
      height: height,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _value,
          builder: (context, _) {
            final v = _value.value;
            final base = v.floor();
            return Stack(
              clipBehavior: Clip.none,
              children: [
                for (final d in [base, base + 1])
                  if ((d - v).abs() < 1)
                    Positioned(
                      left: 0,
                      top: (d - v) * height,
                      child: Text('${d % 10}', style: widget.style),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}
