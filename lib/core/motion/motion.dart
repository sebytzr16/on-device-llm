import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import 'motion_choice.dart';

export 'blur_switcher.dart';
export 'haptics.dart';
export 'motion_choice.dart';
export 'pressable.dart';
export 'marquee_text.dart';
export 'rolling_text.dart';
export 'spring_controls.dart';
export 'spring_entrance.dart';
export 'spring_routes.dart';
export 'spring_size.dart';
export 'streaming_reveal.dart';

/// The house motion, measured frame by frame from the tester's reference
/// clips (2026-09-26): springs with about 5 % overshoot that settle in
/// roughly 0.45 s, and contents that blur out and back in while their
/// container changes shape.
abstract final class AppMotion {
  /// A spring from a damping ratio (1 = no overshoot) and a response in
  /// seconds (the period of the undamped oscillation: how quick it feels).
  static SpringDescription spring({
    double dampingRatio = 0.7,
    double response = 0.35,
  }) {
    final stiffness = math.pow(2 * math.pi / response, 2).toDouble();
    return SpringDescription(
      mass: 1,
      stiffness: stiffness,
      damping: 4 * math.pi * dampingRatio / response,
    );
  }

  /// Pills, cards, sheets, banners.
  static final SpringDescription standard = spring();

  /// Small controls that answer the finger at once (press, knobs).
  static final SpringDescription snappy = spring(response: 0.26);

  /// A success check or a badge landing: a little more rebound.
  static final SpringDescription pop = spring(dampingRatio: 0.5, response: 0.3);

  /// The Subtle level: the same speed without overshoot.
  static final SpringDescription calm = spring(dampingRatio: 1, response: 0.3);

  static const Duration fadeIn = Duration(milliseconds: 220);
  static const Duration fadeOut = Duration(milliseconds: 140);

  /// A value or scroll that follows something live: a progress fill, the
  /// captions growing as they are spoken.
  static const Duration track = Duration(milliseconds: 280);

  /// A deliberate scroll or layout move: to the latest answer, back to the
  /// top of a form, the orb making room for the captions.
  static const Duration glide = Duration(milliseconds: 420);

  /// The curve for the few tweens that cannot be springs (scrolls, fills).
  static const Curve ease = Curves.easeOutCubic;

  /// The one breath every looping effect shares: the thinking shimmer, the
  /// typing dots, the preparing ring and the thinking wave. Loops run whole
  /// multiples of it from one clock, so effects on screen together pulse in
  /// step instead of each keeping its own time.
  static const Duration ambient = Duration(milliseconds: 2400);

  /// Where the shared breath is now, from 0 to 1.
  static double ambientPhase() {
    final period = ambient.inMicroseconds;
    return (DateTime.now().microsecondsSinceEpoch % period) / period;
  }

  /// Blur of content leaving or entering a morphing container.
  static const double blurSigma = 6;
}

/// The motion level for everything below it; set once above the navigator.
class MotionScope extends InheritedWidget {
  final MotionChoice choice;
  const MotionScope({super.key, required this.choice, required super.child});

  static MotionChoice of(BuildContext context) {
    final choice =
        context.dependOnInheritedWidgetOfExactType<MotionScope>()?.choice ??
        MotionChoice.full;
    // Android's "Remove animations" (and the iOS equivalent) wins.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return MotionChoice.off;
    }
    return choice;
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) => oldWidget.choice != choice;
}

/// What the motion level allows, read in build via `context.motion`.
@immutable
class Motion {
  final MotionChoice choice;
  const Motion(this.choice);

  bool get animates => choice != MotionChoice.off;
  bool get full => choice == MotionChoice.full;

  /// Blur crossfades, squash and extra rebound only at Full.
  bool get blur => full;
  SpringDescription get spring => full ? AppMotion.standard : AppMotion.calm;
  SpringDescription get snappy => full ? AppMotion.snappy : AppMotion.calm;
  SpringDescription get pop => full ? AppMotion.pop : AppMotion.calm;
  Duration fade(Duration d) => animates ? d : Duration.zero;
}

extension MotionContext on BuildContext {
  Motion get motion => Motion(MotionScope.of(this));
}

extension SpringTo on AnimationController {
  /// Springs to [target] from the current value and velocity, so a change
  /// of mind mid-flight stays smooth. Jumps when [animate] is false.
  void springTo(
    double target,
    SpringDescription spring, {
    bool animate = true,
  }) {
    if (!animate) {
      stop();
      value = target;
      return;
    }
    // A spring stops within a hair of its target: land exactly on it.
    unawaited(
      animateWith(SpringSimulation(spring, value, target, velocity)).then((_) {
        if (value != target) value = target;
      }),
    );
  }
}

extension AmbientLoop on AnimationController {
  /// Loops on the shared breath ([AppMotion.ambient] must be this
  /// controller's duration), in phase with every other loop on screen.
  /// Holds at rest when [animate] is false.
  void loopAmbient({required bool animate}) {
    if (!animate) {
      if (isAnimating) stop();
      if (value != 0) value = 0;
      return;
    }
    if (isAnimating) return;
    value = AppMotion.ambientPhase();
    repeat();
  }
}

extension GlideTo on ScrollController {
  /// Scrolls to [offset] on the house ease, or jumps there when motion is
  /// off.
  Future<void> glideTo(
    double offset,
    Motion motion, {
    Duration duration = AppMotion.glide,
  }) {
    if (!motion.animates) {
      jumpTo(offset);
      return Future.value();
    }
    return animateTo(offset, duration: duration, curve: AppMotion.ease);
  }
}

/// Holds at its start for [delay] seconds, then follows [inner]; lets rows
/// cascade without timers.
class DelayedSimulation extends Simulation {
  final double delay;
  final Simulation inner;
  DelayedSimulation(this.delay, this.inner);

  @override
  double x(double time) => time < delay ? inner.x(0) : inner.x(time - delay);

  @override
  double dx(double time) => time < delay ? 0 : inner.dx(time - delay);

  @override
  bool isDone(double time) => time >= delay && inner.isDone(time - delay);
}
