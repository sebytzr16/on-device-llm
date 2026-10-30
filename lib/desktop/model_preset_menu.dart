import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../features/settings/presentation/providers/model_profiles_provider.dart';
import '../features/settings/presentation/providers/model_sampling_variants_provider.dart';

/// Shared model variant selector. The load dialog supplies its unsaved profile.
class DesktopModelPresetMenu extends ConsumerWidget {
  final String modelId;
  final bool pill;
  final Map<String, dynamic>? profile;
  final ValueChanged<Map<String, dynamic>>? onActivated;
  const DesktopModelPresetMenu({
    super.key,
    required this.modelId,
    this.pill = false,
    this.profile,
    this.onActivated,
  });

  Map<String, dynamic> _current(WidgetRef ref) =>
      profile ?? ref.read(modelProfilesProvider.notifier).of(modelId);

  Future<String?> _name(
    BuildContext context,
    WidgetRef ref, {
    String? initial,
  }) async {
    final names = ref
        .read(modelSamplingVariantsProvider.notifier)
        .of(modelId)
        .variants
        .map((v) => v.name)
        .toSet();
    return showAppDialog<String>(
      context: context,
      builder: (_) => _VariantNameDialog(initial: initial, names: names),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final t = context.l10n;
    var name = await _name(context, ref);
    if (name == null || !context.mounted) return;
    var values = modelSamplingValues(_current(ref));
    final suggestion = name.startsWith('\u0000');
    if (suggestion) {
      final precise = name == '\u0000precise';
      name = precise
          ? t.desktopModelPresetPrecise
          : t.desktopModelPresetCreative;
      values = {
        ...values,
        'temperature': precise ? 0.2 : 1.0,
        'topP': precise ? 0.9 : 0.95,
      };
      final base = name;
      var n = 2;
      while (ref
          .read(modelSamplingVariantsProvider.notifier)
          .of(modelId)
          .variants
          .any((v) => v.name == name)) {
        name = '$base (${n++})';
      }
    }
    final notifier = ref.read(modelSamplingVariantsProvider.notifier);
    await notifier.save(modelId, name!, values: values);
    if (suggestion) {
      await notifier.activate(modelId, name);
      onActivated?.call(ref.read(modelProfilesProvider.notifier).of(modelId));
    }
  }

  Future<void> _manage(
    BuildContext context,
    WidgetRef ref,
  ) => showAppDialog<void>(
    context: context,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final t = context.l10n;
        final value =
            ref.watch(modelSamplingVariantsProvider)[modelId] ??
            const ModelSamplingVariants();
        final notifier = ref.read(modelSamplingVariantsProvider.notifier);
        return AlertDialog(
          title: Text(t.desktopModelPresetManage),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (value.variants.isEmpty) Text(t.desktopModelPresetEmpty),
                  for (final v in value.variants)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(v.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: t.desktopModelPresetUpdate,
                            icon: const Icon(Icons.save_outlined),
                            onPressed: () => notifier.update(
                              modelId,
                              v.name,
                              values: _current(ref),
                            ),
                          ),
                          IconButton(
                            tooltip: t.desktopModelPresetRename,
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final name = await _name(
                                context,
                                ref,
                                initial: v.name,
                              );
                              if (name != null) {
                                await notifier.rename(modelId, v.name, name);
                              }
                            },
                          ),
                          IconButton(
                            tooltip: t.desktopModelPresetDelete,
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => notifier.delete(modelId, v.name),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t.desktopInspectorClose),
            ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final value =
        ref.watch(modelSamplingVariantsProvider)[modelId] ??
        const ModelSamplingVariants();
    final current =
        profile ??
        ref.watch(modelProfilesProvider)[modelId] ??
        const <String, dynamic>{};
    if (pill && value.variants.isEmpty) return const SizedBox.shrink();
    final label = value.active ?? t.desktopModelPresetDefault;
    return PopupMenuButton<(int, String?)>(
      key: Key(
        pill ? 'desktop-model-preset-pill' : 'desktop-model-preset-menu',
      ),
      tooltip: t.desktopModelPresetLabel,
      onSelected: (action) async {
        if (action.$1 == 1) return _save(context, ref);
        if (action.$1 == 2) return _manage(context, ref);
        if (action.$1 == 3) {
          await ref
              .read(modelSamplingVariantsProvider.notifier)
              .update(modelId, value.active!, values: _current(ref));
          return;
        }
        await ref
            .read(modelSamplingVariantsProvider.notifier)
            .activate(modelId, action.$2);
        onActivated?.call(ref.read(modelProfilesProvider.notifier).of(modelId));
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: (0, null),
          checked: value.active == null,
          child: Text(t.desktopModelPresetDefault),
        ),
        for (final v in value.variants)
          CheckedPopupMenuItem(
            value: (0, v.name),
            checked: value.active == v.name,
            child: Text(v.name),
          ),
        const PopupMenuDivider(),
        if (value.active != null)
          PopupMenuItem(
            value: (3, null),
            child: Text(t.desktopModelPresetUpdate),
          ),
        PopupMenuItem(
          value: (1, null),
          child: Text(t.desktopModelPresetSaveAs),
        ),
        PopupMenuItem(
          value: (2, null),
          child: Text(t.desktopModelPresetManage),
        ),
      ],
      child: Container(
        constraints: const BoxConstraints(maxWidth: 220),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: context.colors.hairline),
          borderRadius: BorderRadius.circular(pill ? 20 : 8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: context.text.caption,
              ),
            ),
            if (value.modified(current))
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Tooltip(
                  message: t.desktopModelPresetModified,
                  child: Icon(
                    Icons.circle,
                    key: const Key('desktop-model-preset-modified'),
                    size: 6,
                    color: context.colors.accent,
                  ),
                ),
              ),
            const Icon(Icons.expand_more, size: 16),
          ],
        ),
      ),
    );
  }
}

class _VariantNameDialog extends StatefulWidget {
  final String? initial;
  final Set<String> names;
  const _VariantNameDialog({this.initial, required this.names});

  @override
  State<_VariantNameDialog> createState() => _VariantNameDialogState();
}

class _VariantNameDialogState extends State<_VariantNameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty ||
        (name != widget.initial && widget.names.contains(name))) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return AlertDialog(
      title: Text(
        widget.initial == null
            ? t.desktopModelPresetSaveAs
            : t.desktopModelPresetRename,
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('desktop-model-preset-name'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: t.desktopModelPresetName,
                errorText: _invalid ? t.desktopModelPresetNameError : null,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.initial == null) ...[
              const SizedBox(height: 12),
              Text(
                t.desktopModelPresetSuggestions,
                style: context.text.caption,
              ),
              Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: Text(t.desktopModelPresetPrecise),
                    onPressed: () => Navigator.pop(context, '\u0000precise'),
                  ),
                  ActionChip(
                    label: Text(t.desktopModelPresetCreative),
                    onPressed: () => Navigator.pop(context, '\u0000creative'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(t.save)),
      ],
    );
  }
}
