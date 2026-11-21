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
        if (a.failure case final failure?) ...[
          SettingsNote(
            _failureText(context, failure, a.error),
            tone: c.danger,
            icon: Icons.error_outline,
          ),
          if (notifier.loadFailed)
            SettingsGroup(
              children: [
                SettingsRow(
                  leading: const Icon(Icons.restart_alt),
                  title: Text(context.l10n.reset),
                  onTap: () => _resetAdapters(context, notifier),
                ),
              ],
            ),
        ],
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
                        _reportSaveFailure(context, notifier, e);
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
                  onChanged: (scale) =>
                      _updateAttachment(context, notifier, m.id, ad.id, scale),
                ),
            ],
          ),
      ],
    );
  }
}

/// The store's failure as the user reads it: the kind picks the localized
/// sentence and the store's technical detail stays the placeholder, so its
/// English sentences never reach the page (review #4).
String _failureText(
  BuildContext context,
  AdaptersFailure failure,
  String? detail,
) => switch (failure) {
  AdaptersFailure.unreadable => context.l10n.adapterListUnreadable,
  AdaptersFailure.saveFailed => context.l10n.adapterSaveFailed(detail ?? ''),
  AdaptersFailure.resetFailed => context.l10n.adapterResetFailed(detail ?? ''),
  AdaptersFailure.importFailed => context.l10n.adapterImportFailed(
    detail ?? '',
  ),
};

/// Moves an unreadable manifest aside and starts from an empty list; the only
/// way out of the corrupt-manifest dead end (review #5).
Future<void> _resetAdapters(
  BuildContext context,
  AdaptersNotifier notifier,
) async {
  try {
    await notifier.resetUnreadable();
  } catch (error) {
    if (!context.mounted) return;
    showIslandToast(
      context,
      context.l10n.adapterResetFailed('$error'),
      tone: IslandTone.error,
    );
  }
}

/// Applies or removes an attachment. The save is awaited so a corrupt manifest
/// reports its reason instead of an unhandled async error, and the tap offers
/// the reset that unblocks import, attach and delete (review #5).
Future<void> _updateAttachment(
  BuildContext context,
  AdaptersNotifier notifier,
  String modelId,
  String adapterId,
  double? scale,
) async {
  try {
    if (scale == null) {
      await notifier.detach(modelId, adapterId);
    } else {
      await notifier.attach(modelId, adapterId, scale);
    }
  } catch (error) {
    if (!context.mounted) return;
    _reportSaveFailure(context, notifier, error);
  }
}

/// A refused adapter save (attach, detach or delete) as the user reads it:
/// the blocked save gets the localized sentence and the reset that unblocks
/// it, anything unexpected keeps its technical detail (review #4).
void _reportSaveFailure(
  BuildContext context,
  AdaptersNotifier notifier,
  Object error,
) {
  showIslandToast(
    context,
    error is AdaptersUnreadable ? context.l10n.adapterListUnreadable : '$error',
    tone: IslandTone.error,
    action: IslandAction(
      context.l10n.reset,
      () => _resetAdapters(context, notifier),
    ),
  );
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
          // The scale track is a settings row of its own: full width under
          // the model's label, with the shared card padding.
          SettingsTile(
            title: Slider(
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
