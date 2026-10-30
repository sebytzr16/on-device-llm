import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/settings/domain/schema_validation.dart';
import '../features/settings/domain/settings_scope.dart';
import '../features/settings/presentation/providers/effective_settings_provider.dart';
import '../features/settings/presentation/providers/model_profiles_provider.dart';
import '../features/tools/presentation/tools_quick_panel.dart';
import 'desktop_theme.dart';
import 'model_preset_menu.dart';
import '../features/settings/domain/model_sampling_keys.dart';
export '../features/settings/domain/model_sampling_keys.dart';

/// Whether the chat's right-hand inspector is open (Ctrl+I).
final desktopInspectorOpen = ValueNotifier<bool>(false);

/// LM Studio-style side panel: instructions, sampling, context length,
/// structured output and tools. Sampling is saved with the model by default
/// (people tune each model differently), or with this chat only; structured
/// output and tools always belong to the chat.
class DesktopInspectorPanel extends ConsumerStatefulWidget {
  const DesktopInspectorPanel({super.key});

  static const width = 340.0;

  @override
  ConsumerState<DesktopInspectorPanel> createState() =>
      _DesktopInspectorPanelState();
}

class _DesktopInspectorPanelState extends ConsumerState<DesktopInspectorPanel> {
  final _prompt = TextEditingController();
  final _structured = TextEditingController();
  String? _shownPrompt;
  bool _chatScope = false;

  @override
  void dispose() {
    _prompt.dispose();
    _structured.dispose();
    super.dispose();
  }

  static Map<String, dynamic> _changed(
    InferenceSettings from,
    InferenceSettings next,
  ) {
    final before = from.toJson(), after = next.toJson();
    return {
      for (final key in before.keys)
        if (before[key] != after[key]) key: after[key],
    };
  }

  /// Into this chat's overrides: structured output and tools, and the
  /// model settings while the scope is "This chat".
  void _update(InferenceSettings from, InferenceSettings next) {
    ref.read(chatProvider.notifier).setChatOverrides({
      ...ref.read(chatOverridesProvider),
      ..._changed(from, next),
    });
  }

  /// Into the model's profile, or the chat's when [_chatScope]. A model
  /// edit also drops the chat's own value for that key, so it shows.
  void _updateModel(
    String? modelId,
    InferenceSettings from,
    InferenceSettings next,
  ) {
    if (_chatScope || modelId == null) return _update(from, next);
    final changed = _changed(from, next);
    final profiles = ref.read(modelProfilesProvider.notifier);
    profiles.set(modelId, {...profiles.of(modelId), ...changed});
    final chat = ref.read(chatOverridesProvider);
    if (changed.keys.any(chat.containsKey)) {
      ref.read(chatProvider.notifier).setChatOverrides({
        for (final e in chat.entries)
          if (!changed.containsKey(e.key)) e.key: e.value,
      });
    }
  }

  void _reset(String? modelId) {
    if (_chatScope || modelId == null) {
      ref.read(chatProvider.notifier).setChatOverrides({});
      return;
    }
    final profiles = ref.read(modelProfilesProvider.notifier);
    profiles.set(modelId, {
      for (final e in profiles.of(modelId).entries)
        if (!desktopSamplingKeys.contains(e.key) && e.key != 'contextSize')
          e.key: e.value,
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.l10n;
    final resolved = ref.watch(effectiveSettingsProvider);
    final s = resolved.effective;
    final modelId = ref.watch(activeModelIdProvider);
    final model = ref
        .watch(modelManagerProvider)
        .catalog
        .where((m) => m.id == modelId)
        .firstOrNull;
    final chatScope = _chatScope || model == null;
    String? source(String key) =>
        desktopSettingSource(t, resolved.originOf(key));
    void set(InferenceSettings next) => _updateModel(modelId, s, next);
    // Follow the chat's prompt unless the field holds an unsaved edit.
    if (_shownPrompt != s.systemPrompt) {
      _shownPrompt = s.systemPrompt;
      _prompt.text = s.systemPrompt;
    }
    final structured = s.responseFormat == ResponseFormat.gbnf
        ? s.grammar
        : s.jsonSchema;
    if (_structured.text != structured) _structured.text = structured;
    final schemaError = switch (validateJsonSchema(s.jsonSchema)) {
      SchemaProblem.empty => t.structuredSchemaEmpty,
      SchemaProblem.objectRequired => t.structuredSchemaObject,
      SchemaProblem.invalidJson => t.structuredSchemaInvalid,
      null => null,
    };
    final overridden = chatScope
        ? ref.watch(chatOverridesProvider).isNotEmpty
        : ref
                  .watch(modelProfilesProvider)[modelId]
                  ?.keys
                  .any(
                    (k) =>
                        desktopSamplingKeys.contains(k) || k == 'contextSize',
                  ) ??
              false;
    return Container(
      width: DesktopInspectorPanel.width,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(left: BorderSide(color: c.hairline)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(t.desktopInspectorTitle, style: context.text.title),
              ),
              if (overridden)
                TextButton(
                  key: const Key('desktop-inspector-reset'),
                  onPressed: () => _reset(modelId),
                  child: Text(
                    chatScope
                        ? t.desktopInspectorReset
                        : t.desktopInspectorResetModel,
                  ),
                ),
              IconButton(
                tooltip: t.desktopInspectorClose,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => desktopInspectorOpen.value = false,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const Key('desktop-inspector-scope'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: false,
                enabled: model != null,
                icon: const Icon(Icons.memory_rounded, size: 15),
                label: Text(
                  model?.displayName ?? t.desktopInspectorScopeModel,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ButtonSegment(
                value: true,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
                label: Text(t.desktopInspectorScopeChat),
              ),
            ],
            selected: {chatScope},
            onSelectionChanged: (v) => setState(() => _chatScope = v.first),
          ),
          if (!chatScope && modelId != null)
            DesktopModelPresetMenu(modelId: modelId),
          const SizedBox(height: 8),
          Text(
            chatScope
                ? t.desktopInspectorHint
                : t.desktopInspectorModelHint(model.displayName),
            style: context.text.caption.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: 16),
          _Label(t.desktopInspectorSystemPrompt),
          TextField(
            controller: _prompt,
            minLines: 3,
            maxLines: 8,
            style: context.text.body.copyWith(fontSize: 13.5),
            decoration: InputDecoration(
              hintText: chatScope
                  ? t.desktopInspectorPromptHint
                  : t.desktopInspectorModelPromptHint,
            ),
            onChanged: (v) {
              _shownPrompt = v;
              set(s.copyWith(systemPrompt: v));
            },
          ),
          const SizedBox(height: 18),
          DesktopSamplingFields(settings: s, source: source, onChanged: set),
          DesktopSlider(
            label: t.desktopInspectorContext,
            source: source('contextSize'),
            value: s.contextSize.toDouble(),
            min: 1024,
            max: 32768,
            divisions: 31,
            format: (v) => '${(v / 1024).round()}K',
            onChanged: (v) =>
                set(s.copyWith(contextSize: (v / 1024).round() * 1024)),
          ),
          Text(
            t.desktopInspectorContextHint,
            style: context.text.caption.copyWith(color: c.textFaint),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  t.desktopInspectorChatSection,
                  style: context.text.label,
                ),
              ),
              // The header's reset covers the model in model scope; this
              // one clears what the chat holds (structured output, tools).
              if (!chatScope && ref.watch(chatOverridesProvider).isNotEmpty)
                TextButton(
                  key: const Key('desktop-inspector-reset-chat'),
                  onPressed: () =>
                      ref.read(chatProvider.notifier).setChatOverrides({}),
                  child: Text(t.desktopInspectorReset),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _Label(t.uiAdvancedStructuredOutputPageStructuredOutput),
          DropdownButtonFormField<ResponseFormat>(
            key: ValueKey(s.responseFormat),
            initialValue: s.responseFormat,
            isExpanded: true,
            items: [
              for (final format in ResponseFormat.values)
                DropdownMenuItem(
                  value: format,
                  child: Text(switch (format) {
                    ResponseFormat.text => t.structuredFormatText,
                    ResponseFormat.json => t.structuredFormatJson,
                    ResponseFormat.jsonSchema =>
                      t.uiAdvancedStructuredOutputPageJSONSchema,
                    ResponseFormat.gbnf => t.structuredFormatGrammar,
                  }),
                ),
            ],
            onChanged: (v) {
              if (v != null) _update(s, s.copyWith(responseFormat: v));
            },
          ),
          if (s.responseFormat == ResponseFormat.jsonSchema ||
              s.responseFormat == ResponseFormat.gbnf) ...[
            const SizedBox(height: 8),
            TextField(
              key: const Key('desktop-structured-editor'),
              controller: _structured,
              minLines: 4,
              maxLines: 10,
              style: context.text.mono.copyWith(fontSize: 12),
              decoration: InputDecoration(
                errorText: s.responseFormat == ResponseFormat.jsonSchema
                    ? schemaError
                    : s.grammar.trim().isEmpty
                    ? t.structuredGrammarEmpty
                    : null,
                errorMaxLines: 3,
              ),
              onChanged: (v) => _update(
                s,
                s.responseFormat == ResponseFormat.gbnf
                    ? s.copyWith(grammar: v)
                    : s.copyWith(jsonSchema: v),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            t.structuredSmallModelHint,
            style: context.text.caption.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: 16),
          _Label(t.uiToolsQuickPanelToolUse),
          ClipRRect(
            borderRadius: AppDesign.radius(AppDesign.rMd),
            child: const Material(
              type: MaterialType.transparency,
              child: ToolsQuickPanel(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text.toUpperCase(),
      style: context.text.mono.copyWith(
        fontSize: 11,
        color: context.colors.textMuted,
        letterSpacing: 0.8,
      ),
    ),
  );
}

/// A labelled slider with its value in amber mono, shared by the desktop
/// inspector and load settings.
class DesktopSlider extends StatelessWidget {
  final String label;

  /// Where the value comes from (the model's makers, its profile, this
  /// chat…), shown faint next to it.
  final String? source;
  final double value, min, max;
  final int divisions;
  final String Function(double) format;
  final ValueChanged<double> onChanged;
  const DesktopSlider({
    super.key,
    required this.label,
    this.source,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.format,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final v = value.clamp(min, max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _Label(label)),
            if (source != null)
              Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 6),
                child: Text(
                  source!,
                  style: context.text.caption.copyWith(
                    fontSize: 11,
                    color: context.colors.textFaint,
                  ),
                ),
              ),
            Text(
              format(v),
              style: context.text.mono.copyWith(
                fontSize: 12,
                color: context.colors.accent,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: v,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

/// Short name of the cascade layer a value comes from; null for the app's
/// own default (nothing worth pointing at).
String? desktopSettingSource(AppLocalizations t, String layer) =>
    switch (layer) {
      SettingsLayer.idRecommended => t.desktopSourceMaker,
      SettingsLayer.idGlobal => t.desktopSourceYours,
      SettingsLayer.idModel => t.desktopSourceModel,
      SettingsLayer.idPreset => t.desktopSourcePreset,
      SettingsLayer.idProject => t.desktopSourceProject,
      SettingsLayer.idChat || SettingsLayer.idTurn => t.desktopSourceChat,
      _ => null,
    };

/// The sampling sliders a model profile or a chat can set, shared by the
/// inspector and the model settings dialog.
class DesktopSamplingFields extends StatelessWidget {
  final InferenceSettings settings;
  final String? Function(String key)? source;
  final ValueChanged<InferenceSettings> onChanged;
  const DesktopSamplingFields({
    super.key,
    required this.settings,
    this.source,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final s = settings;
    String fixed(double v) => v.toStringAsFixed(2);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DesktopSlider(
          key: const Key('desktop-temperature'),
          label: t.desktopInspectorTemperature,
          source: source?.call('temperature'),
          value: s.temperature,
          min: 0,
          max: 2,
          divisions: 40,
          format: fixed,
          onChanged: (v) => onChanged(s.copyWith(temperature: v)),
        ),
        DesktopSlider(
          label: 'Top P',
          source: source?.call('topP'),
          value: s.topP,
          min: 0,
          max: 1,
          divisions: 20,
          format: fixed,
          onChanged: (v) => onChanged(s.copyWith(topP: v)),
        ),
        DesktopSlider(
          label: 'Min P',
          source: source?.call('minP'),
          value: s.minP,
          min: 0,
          max: 0.5,
          divisions: 50,
          format: fixed,
          onChanged: (v) => onChanged(s.copyWith(minP: v)),
        ),
        DesktopSlider(
          label: 'Top K',
          source: source?.call('topK'),
          value: s.topK.toDouble(),
          min: 0,
          max: 200,
          divisions: 200,
          format: (v) => v.round().toString(),
          onChanged: (v) => onChanged(s.copyWith(topK: v.round())),
        ),
        DesktopSlider(
          label: t.desktopInspectorRepeatPenalty,
          source: source?.call('repetitionPenalty'),
          value: s.repetitionPenalty,
          min: 1,
          max: 2,
          divisions: 40,
          format: fixed,
          onChanged: (v) => onChanged(s.copyWith(repetitionPenalty: v)),
        ),
        DesktopSlider(
          label: t.desktopInspectorPresencePenalty,
          source: source?.call('presencePenalty'),
          value: s.presencePenalty,
          min: 0,
          max: 2,
          divisions: 40,
          format: fixed,
          onChanged: (v) => onChanged(s.copyWith(presencePenalty: v)),
        ),
        DesktopSlider(
          label: t.desktopInspectorMaxTokens,
          source: source?.call('maxTokens'),
          value: s.maxTokens.toDouble(),
          min: 256,
          max: 16384,
          divisions: 63,
          format: (v) => v.round().toString(),
          onChanged: (v) => onChanged(s.copyWith(maxTokens: v.round())),
        ),
      ],
    );
  }
}

/// The inspector slides in from the right edge of the chat.
class DesktopInspectorSlot extends StatelessWidget {
  const DesktopInspectorSlot({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: desktopInspectorOpen,
    builder: (context, open, _) => AnimatedSize(
      duration: DesktopTheme.medium,
      curve: DesktopTheme.curve,
      alignment: Alignment.centerLeft,
      child: open ? const DesktopInspectorPanel() : const SizedBox.shrink(),
    ),
  );
}
