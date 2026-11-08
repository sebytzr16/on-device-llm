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
    final schemaProblem = s.responseFormat == ResponseFormat.jsonSchema
        ? switch (validateJsonSchema(s.jsonSchema)) {
            SchemaProblem.empty => context.l10n.structuredSchemaEmpty,
            SchemaProblem.objectRequired => context.l10n.structuredSchemaObject,
            SchemaProblem.invalidJson => context.l10n.structuredSchemaInvalid,
            null => null,
          }
        : null;
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
                ResponseFormat.text => context.l10n.outputFreeText,
                ResponseFormat.json => context.l10n.outputJsonAnyObject,
                ResponseFormat.jsonSchema => context.l10n.outputJsonSchema,
                ResponseFormat.gbnf =>
                  context.l10n.uiAdvancedStructuredOutputPageGBNFGrammar,
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
                      ? context.l10n.structuredGrammarEmpty
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
        SettingsNote(context.l10n.structuredOutputLimitHint),
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
