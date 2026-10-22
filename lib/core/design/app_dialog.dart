import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../motion/motion.dart';
import 'app_design.dart';

/// Opens a dialog the way every dialog in the app opens: it springs up
/// from a little smaller while it fades in, and fades out quicker than it
/// came. Takes the same options as [showDialog] the app uses.
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  return navigator.push(
    _SpringDialogRoute<T>(
      context: context,
      builder: builder,
      motion: context.motion,
      barrierDismissible: barrierDismissible,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    ),
  );
}

/// A yes/no question with Cancel (or [cancelLabel]) and one confirming
/// button; the button is red when [destructive]. True only when the user
/// confirmed.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
  Key? confirmKey,
}) async {
  AppHaptics.tick();
  final ok = await showAppDialog<bool>(
    context: context,
    builder: (dialog) {
      final c = dialog.colors;
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(cancelLabel ?? dialog.l10n.cancel),
          ),
          FilledButton(
            key: confirmKey,
            style: destructive ? dangerButtonStyle(c) : null,
            onPressed: () {
              if (destructive) AppHaptics.press();
              Navigator.pop(dialog, true);
            },
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}

/// The red filled button every destructive confirm uses.
ButtonStyle dangerButtonStyle(AppColors c) =>
    FilledButton.styleFrom(backgroundColor: c.danger, foregroundColor: c.ink);

/// Asks for a line (or a few lines) of text. Returns the trimmed text, or
/// null when the user cancelled. Empty text is only accepted when
/// [allowEmpty] (clearing a value); otherwise the confirm button waits.
/// The initial text starts selected unless [selectAll] is false (editing
/// a long text puts the cursor at the end instead).
/// The dialog owns its controller, so nothing is disposed while it is
/// still fading out.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? message,
  String initial = '',
  String? hint,
  String? helper,
  TextStyle? style,
  required String confirmLabel,
  int minLines = 1,
  int maxLines = 1,
  int? maxLength,
  bool allowEmpty = false,
  bool selectAll = true,
  String? Function(String text)? validate,
  TextInputType? keyboardType,
  Key? fieldKey,
  Key? confirmKey,
}) {
  AppHaptics.tick();
  return showAppDialog<String>(
    context: context,
    builder: (_) => _PromptDialog(
      title: title,
      message: message,
      initial: initial,
      hint: hint,
      helper: helper,
      style: style,
      confirmLabel: confirmLabel,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      allowEmpty: allowEmpty,
      selectAll: selectAll,
      validate: validate,
      keyboardType: keyboardType,
      fieldKey: fieldKey,
      confirmKey: confirmKey,
    ),
  );
}

class _PromptDialog extends StatefulWidget {
  final String title, initial, confirmLabel;
  final String? message, hint, helper;
  final TextStyle? style;
  final int minLines, maxLines;
  final int? maxLength;
  final bool allowEmpty, selectAll;
  final String? Function(String text)? validate;
  final TextInputType? keyboardType;
  final Key? fieldKey, confirmKey;
  const _PromptDialog({
    required this.title,
    required this.message,
    required this.initial,
    required this.hint,
    required this.helper,
    required this.style,
    required this.confirmLabel,
    required this.minLines,
    required this.maxLines,
    required this.maxLength,
    required this.allowEmpty,
    required this.selectAll,
    required this.validate,
    required this.keyboardType,
    required this.fieldKey,
    required this.confirmKey,
  });

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  String? _error;
  late final _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: widget.selectAll ? 0 : widget.initial.length,
      extentOffset: widget.initial.length,
    );

  bool get _ready => widget.allowEmpty || _controller.text.trim().isNotEmpty;

  void _submit() {
    if (!_ready) return;
    final text = _controller.text.trim();
    final error = widget.validate?.call(text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (message != null) ...[
              Text(message, style: context.text.bodyMuted),
              const SizedBox(height: AppDesign.md),
            ],
            TextField(
              key: widget.fieldKey,
              controller: _controller,
              autofocus: true,
              minLines: widget.minLines,
              maxLines: widget.maxLines,
              maxLength: widget.maxLength,
              keyboardType: widget.keyboardType,
              style: widget.style,
              decoration: InputDecoration(
                hintText: widget.hint,
                helperText: widget.helper,
                errorText: _error,
              ),
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: widget.maxLines == 1 ? (_) => _submit() : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          key: widget.confirmKey,
          onPressed: _ready ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _SpringDialogRoute<T> extends DialogRoute<T> {
  final Motion motion;
  _SpringDialogRoute({
    required super.context,
    required super.builder,
    required this.motion,
    super.barrierDismissible,
    super.themes,
  }) : super(barrierColor: Colors.black54);

  CurvedAnimation? _scale, _fade;

  @override
  Duration get transitionDuration => motion.fade(AppMotion.glide);

  @override
  Duration get reverseTransitionDuration => motion.fade(AppMotion.fadeIn);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    _scale ??= CurvedAnimation(
      parent: animation,
      curve: SpringCurve(
        motion.spring,
        seconds: AppMotion.glide.inMilliseconds / 1000,
      ),
      reverseCurve: Curves.easeInCubic,
    );
    _fade ??= CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.5, curve: Curves.easeOut),
      reverseCurve: Curves.easeIn,
    );
    return FadeTransition(
      opacity: _fade!,
      child: ScaleTransition(
        scale: Tween(begin: 0.92, end: 1.0).animate(_scale!),
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _scale?.dispose();
    _fade?.dispose();
    super.dispose();
  }
}
