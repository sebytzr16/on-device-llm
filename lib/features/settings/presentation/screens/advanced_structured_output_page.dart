part of 'advanced_pages_2.dart';

// JSON, JSON Schema and GBNF output.

/// Structured output (roadmap P2): JSON, JSON Schema or GBNF constrained
/// decoding, with validation reported after each answer.
class StructuredOutputPage extends ConsumerWidget {
  const StructuredOutputPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final c = context.colors;
    String? schemaProblem;
    if (s.responseFormat == ResponseFormat.jsonSchema) {
      if (s.jsonSchema.trim().isEmpty) {
        schemaProblem = 'No schema: any JSON object will be accepted.';
      } else {
        try {
          final v = jsonDecode(s.jsonSchema);
          if (v is! Map) schemaProblem = 'The schema must be a JSON object.';
        } catch (e) {
          schemaProblem = 'The schema is not valid JSON.';
        }
      }
    }
    return _Scaffold(
      title: context.l10n.uiAdvancedStructuredOutputPageStructuredOutput,
      children: [
        SettingsGroup(
          children: [
            SettingDropdown<ResponseFormat>(
              icon: Icons.data_object_rounded,
              label: context.l10n.uiAdvancedStructuredOutputPageResponseFormat,
              hint: context
                  .l10n
                  .uiAdvancedStructuredOutputPageConstrainsEveryTokenTheModelProduces,
              value: s.responseFormat,
              items: ResponseFormat.values,
              labelOf: (v) => switch (v) {
                ResponseFormat.text => 'Free text',
                ResponseFormat.json => 'JSON (any object)',
                ResponseFormat.jsonSchema => 'JSON matching a schema',
                ResponseFormat.gbnf => 'GBNF grammar',
              },
              onChanged: (v) => n.update(s.copyWith(responseFormat: v)),
            ),
            if (s.responseFormat == ResponseFormat.jsonSchema)
              SettingsRow(
                leading: const Icon(Icons.data_object_rounded),
                key: const Key('json-schema-row'),
                title: Text(
                  context.l10n.uiAdvancedStructuredOutputPageJSONSchema,
                ),
                subtitle: Text(
                  schemaProblem ??
                      (s.jsonSchema.length > 120
                          ? '${s.jsonSchema.substring(0, 117)}…'
                          : s.jsonSchema),
                  style: TextStyle(
                    color: schemaProblem == null ? null : c.warning,
                  ),
                ),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editText(
                  context,
                  title: context.l10n.uiAdvancedStructuredOutputPageJSONSchema,
                  initial: s.jsonSchema,
                  hint:
                      '{"type": "object", "properties": {"title": {"type": "string"}, "year": {"type": "integer"}}, "required": ["title"]}',
                  onSave: (v) => n.update(s.copyWith(jsonSchema: v)),
                ),
              ),
            if (s.responseFormat == ResponseFormat.gbnf)
              SettingsRow(
                leading: const Icon(Icons.rule_rounded),
                key: const Key('grammar-row'),
                title: Text(
                  context.l10n.uiAdvancedStructuredOutputPageGBNFGrammar,
                ),
                subtitle: Text(
                  s.grammar.trim().isEmpty
                      ? 'No grammar set — the answer will fail until one is given.'
                      : (s.grammar.length > 120
                            ? '${s.grammar.substring(0, 117)}…'
                            : s.grammar),
                  style: TextStyle(
                    color: s.grammar.trim().isEmpty ? c.warning : null,
                  ),
                ),
                trailing: const Icon(Icons.edit_outlined, size: 20),
                onTap: () => _editText(
                  context,
                  title: context.l10n.uiAdvancedStructuredOutputPageGBNFGrammar,
                  initial: s.grammar,
                  hint: 'root ::= answer\nanswer ::= "yes" | "no" | "maybe"',
                  onSave: (v) => n.update(s.copyWith(grammar: v)),
                ),
              ),
          ],
        ),
        const SettingsNote(
          'Constrained answers still stop at Max tokens: a cut-off JSON object is reported as invalid. The format also applies to the remote server through response_format.',
        ),
      ],
    );
  }

  static Future<void> _editText(
    BuildContext context, {
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSave,
  }) async {
    final result = await promptText(
      context,
      title: title,
      initial: initial,
      hint: hint,
      style: context.text.mono.copyWith(color: context.colors.text),
      confirmLabel: context.l10n.uiAdvancedStructuredOutputPageSave,
      maxLines: 12,
      allowEmpty: true,
      selectAll: false,
    );
    if (result != null) await onSave(result);
  }
}
