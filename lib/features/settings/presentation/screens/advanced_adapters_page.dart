part of 'advanced_pages_2.dart';

// LoRA adapters: import and attach to models.

/// LoRA adapters: import files, see what each is for, attach to models.
class AdaptersPage extends ConsumerWidget {
  const AdaptersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(adaptersProvider);
    final notifier = ref.read(adaptersProvider.notifier);
    final models = ref.watch(modelManagerProvider);
    final c = context.colors;
    final downloaded = models.catalog.where((m) => m.isDownloaded).toList();
    return _Scaffold(
      title: context.l10n.uiAdvancedAdaptersPageLoRAAdapters,
      actions: [
        IconButton(
          key: const Key('import-adapter'),
          tooltip: context.l10n.uiAdvancedAdaptersPageImportAdapter,
          onPressed: a.importing
              ? null
              : () async {
                  final picked = await FilePicker.pickFile(type: FileType.any);
                  final path = picked?.path;
                  if (path == null) return;
                  try {
                    await notifier.importFile(path);
                  } catch (_) {
                    // The store reports the reason in its state.
                  }
                },
          icon: const Icon(Icons.add),
        ),
      ],
      children: [
        if (a.error != null)
          SettingsNote(a.error!, tone: c.danger, icon: Icons.error_outline),
        if (a.importing) SettingsNote(context.l10n.adapterImporting),
        if (a.adapters.isEmpty)
          SettingsNote(context.l10n.adapterEmpty, icon: Icons.tune),
        for (final ad in a.adapters)
          SettingsGroup(
            children: [
              SettingsRow(
                title: Text(ad.name),
                subtitle: Text(
                  '${ad.architecture.isEmpty ? context.l10n.adapterUnknownArchitecture : ad.architecture} · ${ad.sizeLabel}'
                  '${ad.alpha > 0 ? ' · alpha ${ad.alpha.toStringAsFixed(0)}' : ''}',
                ),
                trailing: IconButton(
                  tooltip: context.l10n.uiAdvancedAdaptersPageDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await notifier.remove(ad.id);
                    } catch (e) {
                      if (context.mounted) {
                        showIslandToast(context, '$e');
                      }
                    }
                  },
                ),
              ),
              for (final m in downloaded)
                _AttachRow(
                  model: m.displayName,
                  attachment: a
                      .of(m.id)
                      .where((x) => x.adapterId == ad.id)
                      .firstOrNull,
                  onChanged: (scale) => scale == null
                      ? notifier.detach(m.id, ad.id)
                      : notifier.attach(m.id, ad.id, scale),
                ),
            ],
          ),
      ],
    );
  }
}

class _AttachRow extends StatelessWidget {
  final String model;
  final AdapterAttachment? attachment;
  final Future<void> Function(double? scale) onChanged;
  const _AttachRow({
    required this.model,
    required this.attachment,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final on = attachment != null;
    return Column(
      children: [
        SettingsSwitchRow(
          dense: true,
          title: Text(model),
          subtitle: Text(
            on
                ? context.l10n.adapterAppliedAt(
                    attachment!.scale.toStringAsFixed(2),
                  )
                : context.l10n.adapterNotApplied,
          ),
          value: on,
          onChanged: (v) => onChanged(v ? 1.0 : null),
        ),
        if (on)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDesign.lg),
            child: Slider(
              value: attachment!.scale,
              min: -2,
              max: 2,
              divisions: 40,
              label: attachment!.scale.toStringAsFixed(2),
              onChanged: (v) => onChanged(v),
            ),
          ),
      ],
    );
  }
}
