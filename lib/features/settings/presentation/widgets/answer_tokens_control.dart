import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../domain/entities/inference_settings.dart';

/// Uses the loaded engine window when available, without changing the request.
class AnswerTokensSetting extends ConsumerWidget {
  final String label;
  final String? source;
  final int value, contextWindow;
  final bool useLoadedContext, compact;
  final ValueChanged<int> onChanged;
  const AnswerTokensSetting({
    super.key,
    required this.label,
    this.source,
    this.compact = false,
    this.useLoadedContext = true,
    required this.value,
    required this.contextWindow,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(
      chatProvider.select((s) => s.metrics['contextSize']),
    );
    return AnswerTokensControl(
      label: label,
      source: source,
      compact: compact,
      value: value,
      contextWindow: useLoadedContext && loaded is num && loaded > 0
          ? loaded.toInt()
          : contextWindow,
      onChanged: onChanged,
    );
  }
}

/// One answer-limit editor for desktop and phone, including scoped overrides.
class AnswerTokensControl extends StatefulWidget {
  static const sliderMaximum = 64000;
  final String label;
  final String? source;
  final int value, contextWindow;

  /// Desktop inspector style: small caps label, like the other inspector
  /// sliders.
  final bool compact;
  final ValueChanged<int> onChanged;
  const AnswerTokensControl({
    super.key,
    required this.label,
    this.source,
    this.compact = false,
    required this.value,
    required this.contextWindow,
    required this.onChanged,
  });

  /// Positive whole number up to the schema maximum; "128,000" and
  /// "128 000" are accepted.
  static int? parse(String raw) {
    final text = raw.trim();
    final value = RegExp(r'^\d{1,3}([,   .]\d{3})*$|^\d+$').hasMatch(text)
        ? int.tryParse(text.replaceAll(RegExp(r'[,   .]'), ''))
        : null;
    return value != null &&
            value > 0 &&
            value <= InferenceSettings.maxResponseTokens
        ? value
        : null;
  }

  @override
  State<AnswerTokensControl> createState() => _AnswerTokensControlState();
}

class _AnswerTokensControlState extends State<AnswerTokensControl> {
  Future<void> _custom() async {
    final t = context.l10n;
    final raw = await promptText(
      context,
      title: widget.label,
      initial: '${widget.value}',
      helper:
          '1 – ${NumberFormat.decimalPattern().format(InferenceSettings.maxResponseTokens)}',
      confirmLabel: t.uiSettingsWidgetsApply,
      keyboardType: TextInputType.number,
      fieldKey: const Key('answer-tokens-input'),
      validate: (text) => AnswerTokensControl.parse(text) == null
          ? t.answerTokensInvalid
          : null,
    );
    final value = raw == null ? null : AnswerTokensControl.parse(raw);
    if (value != null) widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final number = NumberFormat.decimalPattern(
      Localizations.localeOf(context).toLanguageTag(),
    );
    final compact = widget.compact;
    final label = compact
        ? Text(
            widget.label.toUpperCase(),
            style: context.text.mono.copyWith(
              fontSize: 11,
              color: c.textMuted,
              letterSpacing: 0.8,
            ),
          )
        : Text(widget.label, style: context.text.body.copyWith(fontSize: 14));
    return Padding(
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(
              horizontal: AppDesign.lg,
              vertical: AppDesign.sm,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: label),
              if (widget.source != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    widget.source!,
                    style: context.text.caption.copyWith(
                      fontSize: 11,
                      color: c.textFaint,
                    ),
                  ),
                ),
              Text(
                number.format(widget.value),
                style: context.text.mono.copyWith(
                  fontSize: compact ? 12 : 14,
                  color: c.accent,
                ),
              ),
              const SizedBox(width: 4),
              TextButton(
                key: const Key('answer-tokens-custom'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  textStyle: context.text.caption.copyWith(fontSize: 12),
                ),
                onPressed: _custom,
                child: Text(context.l10n.settingCustomOption),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: widget.value
                  .clamp(1, AnswerTokensControl.sliderMaximum)
                  .toDouble(),
              min: 1,
              max: AnswerTokensControl.sliderMaximum.toDouble(),
              label: number.format(widget.value),
              onChanged: (v) => widget.onChanged(v.round()),
            ),
          ),
          if (widget.value > widget.contextWindow)
            Text(
              context.l10n.answerTokensContextLimit(widget.contextWindow),
              style: context.text.small.copyWith(
                fontSize: 12,
                color: c.textMuted,
              ),
            ),
          if (compact) const SizedBox(height: 4),
        ],
      ),
    );
  }
}
