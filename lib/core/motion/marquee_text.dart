import 'package:flutter/widgets.dart';

/// One line of text that, when it does not fit, slides slowly to the left
/// so the whole line can be read, waits at the end, then comes back
/// (request 2026-10-08: "Report ready · …" and "Group chats with
/// shared…" were cut off in the drawer).
///
/// It plays a few passes and then rests at the start, so it does not keep
/// the screen busy (and widget tests can settle). With animations turned off
/// in the system it wraps onto more lines instead.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;

  /// Slide speed in logical pixels per second: slow enough to read.
  final double speed;
  final Duration pause;
  final int passes;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.speed = 28,
    this.pause = const Duration(milliseconds: 1600),
    this.passes = 3,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);
  Animation<double>? _offset;
  double _overflow = 0;
  int _played = 0;

  @override
  void initState() {
    super.initState();
    _c.addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _played++;
      if (_played < widget.passes && mounted) _c.forward(from: 0);
    });
  }

  @override
  void didUpdateWidget(MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text || old.style != widget.style) {
      _overflow = 0; // measured again on the next layout
      _played = 0;
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _setUp(double overflow) {
    if ((overflow - _overflow).abs() < 0.5) return;
    _overflow = overflow;
    final slide = overflow / widget.speed * 1000;
    final pause = widget.pause.inMilliseconds.toDouble();
    const back = 450.0;
    _c.duration = Duration(
      milliseconds: (pause + slide + pause + back).round(),
    );
    _offset = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0), weight: pause),
      TweenSequenceItem(
        tween: Tween(begin: 0, end: overflow),
        weight: slide,
      ),
      TweenSequenceItem(tween: ConstantTween(overflow), weight: pause),
      TweenSequenceItem(
        tween: Tween(
          begin: overflow,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: back,
      ),
    ]).animate(_c);
    _played = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_c.isAnimating) _c.forward(from: 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Text(widget.text, style: style, maxLines: 3);
    }
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final width = painter.width;
        final height = painter.height;
        painter.dispose();
        final overflow = width - box.maxWidth;
        if (!box.hasBoundedWidth || overflow <= 0) {
          return Text(widget.text, style: style, maxLines: 1, softWrap: false);
        }
        _setUp(overflow);
        final sign = Directionality.of(context) == TextDirection.rtl ? 1 : -1;
        return SizedBox(
          height: height,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, child) => OverflowBox(
                alignment: AlignmentDirectional.centerStart,
                maxWidth: double.infinity,
                child: Transform.translate(
                  offset: Offset(sign * (_offset?.value ?? 0), 0),
                  child: child,
                ),
              ),
              child: Text(
                widget.text,
                style: style,
                maxLines: 1,
                softWrap: false,
              ),
            ),
          ),
        );
      },
    );
  }
}
