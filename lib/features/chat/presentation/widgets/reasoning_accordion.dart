import 'package:flutter/material.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/motion/motion.dart';

/// The model's thinking channel. Cool-tinted, italic and visually
/// subordinate to the answer: open while it streams, folded once done.
class ReasoningAccordion extends StatefulWidget {
  final String content;
  final bool isComplete;

  /// Time the model spent thinking. When null the widget measures it
  /// itself, from the first reasoning token it saw until completion.
  final Duration? duration;

  const ReasoningAccordion({
    super.key,
    required this.content,
    this.isComplete = false,
    this.duration,
  });

  @override
  State<ReasoningAccordion> createState() => _ReasoningAccordionState();
}

class _ReasoningAccordionState extends State<ReasoningAccordion>
    with TickerProviderStateMixin {
  late final AnimationController _fold, _shimmer;
  late final Animation<double> _expand;
  final _started = DateTime.now();
  Duration? _measured;
  bool _open = false;

  @override
  void initState() {
    super.initState();
    // Opens and folds on the house spring; the slight overshoot shows as a
    // little extra room that settles (never below closed).
    _fold = AnimationController.unbounded(vsync: this);
    _expand = _fold.drive(const _NoUndershoot());
    _shimmer = AnimationController(duration: AppMotion.ambient, vsync: this);
    if (widget.isComplete) {
      _measured = widget.duration;
    } else {
      _open = true;
      _fold.value = 1;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.isComplete) {
      _shimmer.loopAmbient(animate: context.motion.animates);
    }
  }

  @override
  void didUpdateWidget(covariant ReasoningAccordion old) {
    super.didUpdateWidget(old);
    if (widget.isComplete && !old.isComplete) {
      _measured = widget.duration ?? DateTime.now().difference(_started);
      _shimmer.stop();
      _open = false;
      _springFold();
    }
  }

  @override
  void dispose() {
    _fold.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  void _springFold() {
    final motion = context.motion;
    _fold.springTo(_open ? 1 : 0, motion.spring, animate: motion.animates);
  }

  void _toggle() {
    AppHaptics.tick();
    setState(() => _open = !_open);
    _springFold();
  }

  String get _title {
    if (!widget.isComplete) return 'Thinking…';
    final d = _measured ?? widget.duration;
    if (d == null) return 'Reasoning';
    final s = d.inMilliseconds / 1000;
    return 'Reasoning · ${s < 10 ? s.toStringAsFixed(1) : s.round()} s';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tint = c.reasoning;
    return Container(
      margin: const EdgeInsets.only(bottom: AppDesign.md),
      decoration: BoxDecoration(
        color: tint.fade(0.06),
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: tint.fade(0.18)),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: AppDesign.radius(AppDesign.rMd),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppDesign.md,
                vertical: AppDesign.sm + 2,
              ),
              child: Row(
                children: [
                  Icon(Icons.psychology_outlined, size: 16, color: tint),
                  const SizedBox(width: AppDesign.sm),
                  Expanded(
                    child: _Shimmer(
                      animation: _shimmer,
                      active: !widget.isComplete && context.motion.animates,
                      color: tint,
                      child: Text(
                        _title,
                        style: context.text.mono.copyWith(
                          color: tint,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),
                  RotationTransition(
                    turns: Tween(begin: 0.0, end: 0.5).animate(_expand),
                    child: Icon(
                      Icons.expand_more,
                      size: 16,
                      color: tint.fade(0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _expand,
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.md,
                0,
                AppDesign.md,
                AppDesign.md,
              ),
              child: SelectableText(
                widget.content,
                style: context.text.reasoning.copyWith(color: tint.fade(0.85)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft highlight sweeping across the label while the model thinks.
class _Shimmer extends AnimatedWidget {
  final bool active;
  final Color color;
  final Widget child;
  const _Shimmer({
    required Animation<double> animation,
    required this.active,
    required this.color,
    required this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    if (!active) return child;
    final t = (listenable as Animation<double>).value;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment(-1.5 + t * 3, 0),
        end: Alignment(-0.5 + t * 3, 0),
        colors: [color.fade(0.55), color, color.fade(0.55)],
      ).createShader(rect),
      child: child,
    );
  }
}

/// Keeps a spring's dip below zero from turning into a negative size.
class _NoUndershoot extends Animatable<double> {
  const _NoUndershoot();

  @override
  double transform(double t) => t.clamp(0.0, 1.1);
}
