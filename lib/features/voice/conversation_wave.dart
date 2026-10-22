part of 'conversation_screen.dart';

// The voice wave around the orb: its loudness animation and painter.

/// The sound wave: amber ribbons that rest as a calm line, rise with the
/// user's voice while listening, follow the answer while it is spoken and
/// ripple slowly while thinking.
class _Wave extends StatefulWidget {
  final ConversationPhase phase;

  /// Loudness now (0…1 RMS), read every frame.
  final double Function() level;
  final bool muted;
  const _Wave({required this.phase, required this.level, required this.muted});

  @override
  State<_Wave> createState() => _WaveState();
}

class _WaveState extends State<_Wave> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _frame = _WaveFrame();
  var _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Speech sits around 0.02–0.15 RMS: the square root spreads it out.
  static double _loudness(double rms) =>
      (math.sqrt(rms.clamp(0.0, 1.0)) * 2.4).clamp(0.0, 1.0);

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    final f = _frame;
    final target = widget.muted
        ? 0.0
        : switch (widget.phase) {
            ConversationPhase.listening ||
            ConversationPhase.speaking => _loudness(widget.level()),
            ConversationPhase.thinking =>
              0.2 + math.sin(2 * math.pi * AppMotion.ambientPhase()) * 0.08,
            _ => 0.04,
          };
    // Quick to rise with a syllable, slow to settle: no flicker.
    final rate = target > f.amp ? 16.0 : 5.0;
    f.amp += (target - f.amp) * (1 - math.exp(-dt * rate));
    if (context.motion.animates) {
      f.time += dt * (0.6 + f.amp * 1.6);
    }
    f.changed();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label:
          widget.phase == ConversationPhase.speaking ||
              widget.phase == ConversationPhase.thinking
          ? context.l10n.convInterrupt
          : context.l10n.conversationTitle,
      button: true,
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: double.infinity,
          height: math.min(box.maxHeight, 320),
          child: CustomPaint(
            painter: _WavePainter(
              _frame,
              colors: widget.muted
                  ? [c.textFaint, c.surfaceRaised]
                  : [c.accent, c.accentDeep],
            ),
          ),
        ),
      ),
    );
  }
}

class _WaveFrame extends ChangeNotifier {
  var time = 0.0;
  var amp = 0.0;
  void changed() => notifyListeners();
}

class _WavePainter extends CustomPainter {
  final _WaveFrame frame;
  final List<Color> colors;
  _WavePainter(this.frame, {required this.colors}) : super(repaint: frame);

  /// Frequency (cycles across the width), drift speed, height, opacity.
  static const _layers = [
    (2.2, 0.9, 1.0, 0.95),
    (3.1, -1.3, 0.72, 0.55),
    (1.5, 1.7, 0.55, 0.35),
  ];

  /// The shader paints the palette colours; this paint only sets opacity.
  static const _opacity = Color(0xFFFFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, mid = size.height / 2;
    // A calm line at rest, up to almost the full height when loud.
    final amp = 0.025 + frame.amp * 0.975;
    final shader = LinearGradient(
      colors: [
        colors[0].withValues(alpha: 0),
        colors[0],
        colors[1],
        colors[0],
        colors[0].withValues(alpha: 0),
      ],
      stops: const [0, 0.2, 0.5, 0.8, 1],
    ).createShader(Offset.zero & size);
    for (var j = _layers.length - 1; j >= 0; j--) {
      final (freq, speed, height, alpha) = _layers[j];
      final top = Path(), bottom = Path();
      const steps = 96;
      for (var i = 0; i <= steps; i++) {
        final u = i / steps;
        // Tapered ends: the wave grows from the middle.
        final taper = math.pow(math.sin(math.pi * u), 2).toDouble();
        final y =
            mid *
            0.92 *
            amp *
            height *
            taper *
            math.sin(2 * math.pi * freq * u + frame.time * speed * 2.2 + j);
        final x = u * w;
        if (i == 0) {
          top.moveTo(x, mid - y);
          bottom.moveTo(x, mid + y * 0.35);
        } else {
          top.lineTo(x, mid - y);
          bottom.lineTo(x, mid + y * 0.35);
        }
      }
      // A soft body between the ribbon and its faint reflection…
      final body = Path.from(top);
      for (var i = steps; i >= 0; i--) {
        final u = i / steps;
        final taper = math.pow(math.sin(math.pi * u), 2).toDouble();
        final y =
            mid *
            0.92 *
            amp *
            height *
            taper *
            math.sin(2 * math.pi * freq * u + frame.time * speed * 2.2 + j);
        body.lineTo(u * w, mid + y * 0.35);
      }
      body.close();
      canvas.drawPath(
        body,
        Paint()
          ..shader = shader
          ..color = _opacity.withValues(alpha: alpha * 0.16),
      );
      // …a glow under the main ribbon…
      if (j == 0) {
        canvas.drawPath(
          top,
          Paint()
            ..shader = shader
            ..style = PaintingStyle.stroke
            ..strokeWidth = 10
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
            ..color = _opacity.withValues(alpha: 0.5),
        );
      }
      // …and the line itself.
      canvas.drawPath(
        top,
        Paint()
          ..shader = shader
          ..style = PaintingStyle.stroke
          ..strokeWidth = j == 0 ? 3 : 1.6
          ..strokeCap = StrokeCap.round
          ..color = _opacity.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.frame != frame || old.colors != colors;
}
