import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/app_design.dart';
import '../motion/motion.dart';

/// What a message on the island means; decides its glyph and colour.
enum IslandTone { busy, done, info, warning, error }

/// A button on a toast, such as "Undo".
@immutable
class IslandAction {
  final String label;
  final VoidCallback onPressed;
  const IslandAction(this.label, this.onPressed);
}

/// One line on the status island.
@immutable
class IslandMessage {
  final String text;
  final IslandTone tone;
  final IconData? icon;

  /// For [IslandTone.busy]: null spins, 0…1 fills a ring.
  final double? progress;

  /// Shown when the island is tapped open.
  final String? detail;

  /// A button at the end of a toast.
  final IslandAction? action;
  const IslandMessage(
    this.text, {
    this.tone = IslandTone.info,
    this.icon,
    this.progress,
    this.detail,
    this.action,
  });

  @override
  bool operator ==(Object other) =>
      other is IslandMessage &&
      other.text == text &&
      other.tone == tone &&
      other.icon == icon &&
      other.progress == progress &&
      other.detail == detail &&
      other.action == action;

  @override
  int get hashCode => Object.hash(text, tone, icon, progress, detail, action);
}

@immutable
class IslandState {
  /// Something that lasts (a model loading, a web search).
  final IslandMessage? activity;

  /// A short confirmation shown over the activity, then gone.
  final IslandMessage? toast;
  const IslandState({this.activity, this.toast});

  IslandMessage? get showing => toast ?? activity;
}

class IslandController extends Notifier<IslandState> {
  Timer? _toastTimer;

  @override
  IslandState build() {
    ref.onDispose(() => _toastTimer?.cancel());
    return const IslandState();
  }

  void activity(IslandMessage? message) {
    if (message == state.activity) return;
    state = IslandState(activity: message, toast: state.toast);
  }

  void toast(
    String text, {
    IslandTone tone = IslandTone.info,
    IconData? icon,
    String? detail,
    IslandAction? action,
    Duration? duration,
  }) {
    _toastTimer?.cancel();
    state = IslandState(
      activity: state.activity,
      toast: IslandMessage(
        text,
        tone: tone,
        icon: icon,
        detail: detail,
        action: action,
      ),
    );
    // A toast with a button stays long enough to reach it.
    _toastTimer = Timer(
      duration ?? Duration(milliseconds: action == null ? 1900 : 4000),
      dismissToast,
    );
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (state.toast != null) state = IslandState(activity: state.activity);
  }
}

final islandProvider = NotifierProvider<IslandController, IslandState>(
  IslandController.new,
);

/// A short confirmation on the island ("Copied", "Web: Auto"). Falls back
/// to a snackbar where no island is mounted (a page shown on its own).
void showIslandToast(
  BuildContext context,
  String text, {
  IslandTone tone = IslandTone.info,
  IconData? icon,
  String? detail,
  IslandAction? action,
}) => islandToastFor(context)(
  text,
  tone: tone,
  icon: icon,
  detail: detail,
  action: action,
);

typedef IslandToast =
    void Function(
      String text, {
      IslandTone tone,
      IconData? icon,
      String? detail,
      IslandAction? action,
    });

/// Resolves now where toasts go (the island, or a snackbar where none is
/// mounted), for code that shows one after an await.
IslandToast islandToastFor(BuildContext context) {
  if (StatusIsland._mounted == 0) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    return (text, {tone = IslandTone.info, icon, detail, action}) =>
        messenger?.showSnackBar(
          SnackBar(
            content: Text(detail == null ? text : '$text\n$detail'),
            duration: Duration(seconds: action == null ? 2 : 4),
            action: action == null
                ? null
                : SnackBarAction(
                    label: action.label,
                    onPressed: action.onPressed,
                  ),
          ),
        );
  }
  final island = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(islandProvider.notifier);
  return (text, {tone = IslandTone.info, icon, detail, action}) => island.toast(
    text,
    tone: tone,
    icon: icon,
    detail: detail,
    action: action,
  );
}

/// The floating pill under the top bar, above every page: grows out of a
/// dot when something starts, stretches as its text changes, pops a check
/// when it is done and shrinks away. Tap it to open the full text.
class StatusIsland extends ConsumerStatefulWidget {
  const StatusIsland({super.key});

  static int _mounted = 0;

  @override
  ConsumerState<StatusIsland> createState() => _StatusIslandState();
}

class _StatusIslandState extends ConsumerState<StatusIsland> {
  bool _open = false;
  IslandMessage? _last;

  @override
  void initState() {
    super.initState();
    StatusIsland._mounted++;
  }

  @override
  void dispose() {
    StatusIsland._mounted--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = ref.watch(islandProvider.select((s) => s.showing));
    if (message != _last) {
      _last = message;
      _open = false;
    }
    final media = MediaQuery.of(context);
    final c = context.colors;
    final width = media.size.width;
    final canOpen =
        message != null && (message.detail != null || message.text.length > 38);
    return Positioned(
      top: media.viewPadding.top + kToolbarHeight + AppDesign.xs,
      left: 0,
      right: 0,
      child: Center(
        child: IgnorePointer(
          ignoring: message == null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: canOpen ? () => setState(() => _open = !_open) : null,
            child: AnimatedOpacity(
              opacity: message == null ? 0 : 1,
              duration: context.motion.fade(AppMotion.fadeIn),
              child: _IslandSurface(
                open: _open,
                color: c.surfaceOverlay,
                border: c.hairlineStrong,
                // Leaving, the content blurs away while the pill shrinks
                // back to a dot.
                child: SpringSize(
                  child: ConstrainedBox(
                    // Bounded both ways: whatever goes wrong inside, the
                    // island stays island-sized.
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        _open ? 380 : 340,
                        width - AppDesign.xxl * 2,
                      ),
                      maxHeight: _open ? 320 : 56,
                    ),
                    child: BlurSwitcher(
                      child: message == null
                          ? const SizedBox.shrink(key: ValueKey('empty'))
                          : _IslandContent(
                              key: ValueKey((
                                message.text,
                                message.tone,
                                _open,
                              )),
                              message: message,
                              open: _open,
                              onAction: message.action == null
                                  ? null
                                  : () {
                                      AppHaptics.tick();
                                      ref
                                          .read(islandProvider.notifier)
                                          .dismissToast();
                                      message.action!.onPressed();
                                    },
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Background, hairline and shadow painted at whatever size the spring has
/// reached; a pill while it is one line, a rounded card when open.
class _IslandSurface extends StatelessWidget {
  final bool open;
  final Color color, border;
  final Widget child;
  const _IslandSurface({
    required this.open,
    required this.color,
    required this.border,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = open ? AppDesign.rXl - 4 : AppDesign.rFull;
    return CustomPaint(
      painter: _SurfacePainter(color: color, border: border, radius: radius),
      child: ClipRRect(
        clipper: _ShapeClipper(radius),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

class _SurfacePainter extends CustomPainter {
  final Color color, border;
  final double radius;
  const _SurfacePainter({
    required this.color,
    required this.border,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = _ShapeClipper.shape(size, radius);
    canvas.drawShadow(
      Path()..addRRect(rrect),
      const Color(0xFF000000),
      10,
      false,
    );
    canvas.drawRRect(rrect, Paint()..color = color);
    canvas.drawRRect(
      rrect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..color = border,
    );
  }

  @override
  bool shouldRepaint(_SurfacePainter old) =>
      old.color != color || old.border != border || old.radius != radius;
}

class _ShapeClipper extends CustomClipper<RRect> {
  final double radius;
  const _ShapeClipper(this.radius);

  /// [radius], but never more than half the short side: a pill at any size.
  static RRect shape(Size size, double radius) => RRect.fromRectAndRadius(
    Offset.zero & size,
    Radius.circular(math.min(radius, size.shortestSide / 2)),
  );

  @override
  RRect getClip(Size size) => shape(size, radius);

  @override
  bool shouldReclip(_ShapeClipper old) => old.radius != radius;
}

class _IslandContent extends StatelessWidget {
  final IslandMessage message;
  final bool open;
  final VoidCallback? onAction;
  const _IslandContent({
    super.key,
    required this.message,
    required this.open,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) =>
      // Screen readers announce each new status as it replaces the last.
      Semantics(liveRegion: true, container: true, child: _body(context));

  Widget _body(BuildContext context) {
    final c = context.colors;
    final color = switch (message.tone) {
      IslandTone.busy => c.accent,
      IslandTone.done => c.success,
      IslandTone.info => c.textMuted,
      IslandTone.warning => c.warning,
      IslandTone.error => c.danger,
    };
    final glyph = switch (message.tone) {
      IslandTone.busy => SizedBox.square(
        dimension: 14,
        // A tween needs an end value: spin until there is progress to fill.
        child: message.progress == null
            ? CircularProgressIndicator(strokeWidth: 2, color: color)
            : TweenAnimationBuilder<double>(
                tween: Tween(end: message.progress!),
                duration: context.motion.fade(AppMotion.track),
                curve: AppMotion.ease,
                builder: (context, value, _) => CircularProgressIndicator(
                  value: value,
                  strokeWidth: 2,
                  color: color,
                  backgroundColor: color.fade(0.2),
                ),
              ),
      ),
      IslandTone.done => SpringEntrance(
        from: Offset.zero,
        fromScale: 0.3,
        child: Icon(
          message.icon ?? Icons.check_rounded,
          size: 16,
          color: color,
        ),
      ),
      _ => Icon(
        message.icon ??
            switch (message.tone) {
              IslandTone.warning => Icons.warning_amber_rounded,
              IslandTone.error => Icons.error_outline,
              _ => Icons.info_outline,
            },
        size: 16,
        color: color,
      ),
    };
    final text = context.text.small.copyWith(
      height: 1.3,
      color: c.text,
      fontWeight: FontWeight.w500,
    );
    if (!open) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyph,
            const SizedBox(width: AppDesign.sm),
            Flexible(
              child: Text(
                message.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text,
              ),
            ),
            if (message.progress != null) ...[
              const SizedBox(width: AppDesign.sm),
              RollingText(
                '${(message.progress! * 100).round()}%',
                style: context.text.mono.copyWith(color: c.textMuted),
              ),
            ],
            if (message.action case final action?) ...[
              const SizedBox(width: AppDesign.md),
              _ActionPill(label: action.label, onTap: onAction),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 18, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.only(top: 2), child: glyph),
              const SizedBox(width: AppDesign.sm + 2),
              Flexible(child: Text(message.text, style: text)),
            ],
          ),
          if (message.detail != null) ...[
            const SizedBox(height: AppDesign.sm),
            Text(
              message.detail!,
              style: context.text.mono.copyWith(color: c.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// The toast's button: an accent pill at the end of the line.
class _ActionPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _ActionPill({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      child: Pressable(
        child: GestureDetector(
          key: const Key('island-action'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppDesign.md,
              vertical: AppDesign.xs,
            ),
            decoration: BoxDecoration(
              color: c.accent.fade(0.14),
              borderRadius: AppDesign.radius(AppDesign.rFull),
            ),
            child: Text(
              label,
              style: context.text.label.copyWith(
                color: c.accent,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
