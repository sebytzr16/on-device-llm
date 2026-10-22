part of 'conversation_screen.dart';

// The Conversation screen's caption lines and big buttons.

/// One line of the transcript.
class _Line {
  final bool user;
  final String text;

  /// The user is still saying it (a running caption).
  final bool live;
  const _Line(this.user, this.text, {this.live = false});
}

/// A large round control with its name underneath.
class _BigButton extends StatelessWidget {
  static const size = 64.0;
  static const labelWidth = 96.0;
  final String label;
  final Widget child;
  const _BigButton({required this.label, required this.child});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      child,
      const SizedBox(height: AppDesign.xs + 2),
      // Three across: a long label ("Terminer la conversation") wraps
      // instead of pushing the buttons off the screen.
      SizedBox(
        width: labelWidth,
        child: ExcludeSemantics(
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: context.text.small.copyWith(color: context.colors.textFaint),
          ),
        ),
      ),
    ],
  );
}

/// A caption that fades between texts and keeps the latest lines.
class _Caption extends StatelessWidget {
  final String text;
  final TextStyle style;
  final int maxLines;
  const _Caption({
    super.key,
    required this.text,
    required this.style,
    this.maxLines = 4,
  });

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: context.motion.fade(AppMotion.fadeIn),
    child: Text(
      text,
      key: ValueKey(text),
      textAlign: TextAlign.center,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}
