import 'package:flutter/material.dart';

import '../../../../core/motion/motion.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app.dart';
import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/platform/device_info.dart';
import '../../../../core/providers/shared_providers.dart';
import '../../../../inference/remote/remote_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../settings/presentation/screens/remote_server_page.dart';
import '../../domain/entities/model_info.dart';
import '../providers/model_manager_provider.dart';
import '../../domain/entities/model_catalog.dart';
import 'model_tags.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/island/status_island.dart';

/// Bottom sheet listing downloaded models and the saved remote connections.
/// Tapping a model loads it (and turns the remote off); tapping a
/// connection makes it the active remote. One scroll area with compact
/// rows and a pinned footer (library, connections, unload): the old sheet
/// gave each list a share of a fixed height, so with a few connections the
/// phone's models were squeezed into a sliver that could not be scrolled
/// (report, 2026-09-24).
/// It grows out of [from] (the model pill) when given.
Future<void> showModelPickerSheet(BuildContext context, {BuildContext? from}) =>
    showMorphSheet(
      context: context,
      from: from,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.62,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        builder: (context, controller) => _PickerSheet(controller: controller),
      ),
    );

class _PickerSheet extends ConsumerStatefulWidget {
  final ScrollController controller;
  const _PickerSheet({required this.controller});
  @override
  ConsumerState<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends ConsumerState<_PickerSheet> {
  String? _loadingId;

  Future<void> _pick(ModelInfo info) async {
    final toast = islandToastFor(context);
    setState(() => _loadingId = info.id);
    try {
      final settings = ref.read(settingsProvider);
      // A local pick means "answer on this phone" again.
      if (settings.remoteEnabled) {
        await ref
            .read(settingsProvider.notifier)
            .update(settings.copyWith(remoteEnabled: false));
      }
      await ref.read(modelManagerProvider.notifier).loadModel(info);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      toast('$e', tone: IslandTone.error);
      if (mounted) setState(() => _loadingId = null);
    }
  }

  Future<void> _pickRemote(RemoteProfile profile) async {
    final settings = ref.read(settingsProvider);
    await ref
        .read(settingsProvider.notifier)
        .update(
          settings.copyWith(remoteEnabled: true, remoteProfileId: profile.id),
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _unload() async {
    final toast = islandToastFor(context);
    final unloaded = context.l10n.modelUnloaded;
    try {
      final settings = ref.read(settingsProvider);
      if (settings.usesRemote) {
        ref.read(remoteEngineProvider).cancel();
        await ref
            .read(settingsProvider.notifier)
            .update(settings.copyWith(remoteEnabled: false));
      }
      await ref.read(modelManagerProvider.notifier).unloadModel();
      toast(unloaded, tone: IslandTone.done);
    } catch (e) {
      toast('$e', tone: IslandTone.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(modelManagerProvider);
    final memory = ref.watch(deviceMemoryProvider).value;
    final busy = ref.watch(sessionBusyProvider) || state.isLoadingModel;
    final downloaded = state.catalog.where((m) => m.isDownloaded).toList();
    final loadingId = state.isLoadingModel ? _loadingId : null;
    final settings = ref.watch(settingsProvider);
    final remotes = settings.remoteProfiles
        .where((p) => p.uri != null)
        .toList();
    final activeRemote = settings.usesRemote
        ? settings.activeRemoteProfile?.id
        : null;
    final nav = Navigator.of(context);
    return AppSheet(
      title: context.l10n.switchModel,
      scrollable: false,
      primary: Row(
        children: [
          Expanded(
            child: _FooterAction(
              icon: Icons.library_books_outlined,
              label: context.l10n.pickerLibrary,
              onPressed: () {
                nav.pop();
                nav.pushNamed(AppRoutes.models);
              },
            ),
          ),
          Expanded(
            child: _FooterAction(
              key: const Key('picker-remote-settings'),
              icon: Icons.dns_outlined,
              label: context.l10n.pickerConnections,
              onPressed: () {
                nav.pop();
                nav.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const RemoteServerPage(),
                  ),
                );
              },
            ),
          ),
          if (state.loadedModelId != null || settings.usesRemote)
            Expanded(
              child: _FooterAction(
                key: const Key('unload-model'),
                color: c.danger,
                icon: Icons.eject_outlined,
                label: context.l10n.unloadShort,
                onPressed: busy ? null : _unload,
              ),
            ),
        ],
      ),
      children: [
        CustomScrollView(
          controller: widget.controller,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.zero,
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverList.list(
                    children: [
                      if (downloaded.isEmpty) ...[
                        const SizedBox(height: AppDesign.xs),
                        Text(
                          context.l10n.nothingOnPhone,
                          style: context.text.bodyMuted,
                        ),
                      ],
                      if (loadingId != null) ...[
                        const SizedBox(height: AppDesign.md),
                        ClipRRect(
                          borderRadius: AppDesign.radius(AppDesign.rFull),
                          child: const LinearProgressIndicator(minHeight: 3),
                        ),
                        const SizedBox(height: AppDesign.xs),
                        Text(
                          context.l10n.loadingModel,
                          style: context.text.mono,
                        ),
                      ],
                      const SizedBox(height: AppDesign.md),
                      _SectionLabel(
                        icon: Icons.smartphone_outlined,
                        text: context.l10n.onThisDevice,
                        count: downloaded.length,
                      ),
                    ],
                  ),
                  if (downloaded.isEmpty)
                    SliverToBoxAdapter(child: _EmptyState(color: c))
                  else
                    SliverList.separated(
                      itemCount: downloaded.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: AppDesign.md),
                      itemBuilder: (context, index) {
                        final m = downloaded[index];
                        return AppSheetCard(
                          padding: EdgeInsets.zero,
                          child: _ModelRow(
                            model: m,
                            memory: memory,
                            active:
                                activeRemote == null &&
                                state.loadedModelId == m.id,
                            loading: loadingId == m.id,
                            onTap:
                                busy ||
                                    (activeRemote == null &&
                                        state.loadedModelId == m.id)
                                ? null
                                : () => _pick(m),
                          ),
                        );
                      },
                    ),
                  if (remotes.isNotEmpty)
                    SliverMainAxisGroup(
                      slivers: [
                        SliverList.list(
                          children: [
                            const SizedBox(height: AppDesign.lg),
                            _SectionLabel(
                              icon: Icons.cloud_outlined,
                              text: context
                                  .l10n
                                  .uiModelPickerSheetRemoteConnections,
                              count: remotes.length,
                            ),
                          ],
                        ),
                        SliverList.separated(
                          itemCount: remotes.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: AppDesign.md),
                          itemBuilder: (context, index) {
                            final r = remotes[index];
                            return AppSheetCard(
                              padding: EdgeInsets.zero,
                              child: _RemoteRow(
                                profile: r,
                                active: activeRemote == r.id,
                                hasKey: (settings.remoteApiKeys[r.id] ?? '')
                                    .isNotEmpty,
                                onTap: busy || activeRemote == r.id
                                    ? null
                                    : () => _pickRemote(r),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  final int count;
  const _SectionLabel({
    required this.icon,
    required this.text,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.sm),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.textFaint),
          const SizedBox(width: AppDesign.sm),
          Expanded(
            child: Text(
              text,
              style: context.text.label.copyWith(color: c.textMuted),
            ),
          ),
          if (count > 0)
            Text(
              '$count',
              style: context.text.mono.copyWith(color: c.textFaint),
            ),
        ],
      ),
    );
  }
}

class _FooterAction extends StatelessWidget {
  final Color? color;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _FooterAction({
    super.key,
    this.color,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: color ?? context.colors.textMuted,
      padding: const EdgeInsets.symmetric(vertical: AppDesign.sm),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.text.label,
        ),
      ],
    ),
  );
}

/// One compact line per model: name, then "2B · Q4_K_M · 2.44 GB ·
/// reasoning", a memory warning only when it matters.
class _ModelRow extends StatelessWidget {
  final ModelInfo model;
  final DeviceMemory? memory;
  final bool active, loading;
  final VoidCallback? onTap;
  const _ModelRow({
    required this.model,
    required this.memory,
    required this.active,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fit = modelFit(memory, model);
    final params = paramLabel(model);
    final facts = [
      if (params.isNotEmpty) params,
      quantLabel(model),
      model.sizeLabel,
      if (catalogMeta[model.id]?.reasoning == true)
        context.l10n.pickerReasoning,
    ].join(' · ');
    return _Row(
      key: Key('picker-model-${model.id}'),
      active: active,
      onTap: onTap,
      leading: Icons.memory_outlined,
      title: model.displayName,
      subtitle: facts,
      warning: switch (fit) {
        ModelFit.tight => context.l10n.pickerTightRam,
        ModelFit.tooLarge => context.l10n.pickerTooLarge,
        _ => null,
      },
      trailing: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      color: c,
    );
  }
}

/// A saved remote connection in the picker.
class _RemoteRow extends StatelessWidget {
  final RemoteProfile profile;
  final bool active, hasKey;
  final VoidCallback? onTap;
  const _RemoteRow({
    required this.profile,
    required this.active,
    required this.hasKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final provider = profile.provider;
    final detail = [
      if (profile.model.trim().isNotEmpty)
        profile.model.trim()
      else if (provider.selfHosted)
        context.l10n.remoteServerDefaultModel,
      if (profile.label != provider.name) provider.name,
    ].join(' · ');
    return _Row(
      key: Key('picker-remote-${profile.id}'),
      active: active,
      onTap: onTap,
      leading: provider.selfHosted
          ? Icons.computer_outlined
          : Icons.cloud_outlined,
      title: profile.label,
      subtitle: detail,
      warning: provider.requiresKey && !hasKey
          ? context.l10n.pickerNoKey
          : null,
      color: context.colors,
    );
  }
}

class _Row extends StatelessWidget {
  final bool active;
  final VoidCallback? onTap;
  final IconData leading;
  final String title, subtitle;
  final String? warning;
  final Widget? trailing;
  final AppColors color;
  const _Row({
    super.key,
    required this.active,
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.color,
    this.warning,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = color;
    return Material(
      color: active ? c.accent.fade(0.08) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppDesign.md,
            vertical: AppDesign.sm + 2,
          ),
          child: Row(
            children: [
              Icon(leading, size: 20, color: active ? c.accent : c.textFaint),
              const SizedBox(width: AppDesign.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: active ? c.accent : c.text,
                      ),
                    ),
                    if (subtitle.isNotEmpty || warning != null)
                      Text(
                        [
                          subtitle,
                          ?warning,
                        ].where((x) => x.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.mono.copyWith(
                          color: warning != null ? c.warning : c.textFaint,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppDesign.sm),
              trailing ??
                  (active
                      ? Icon(Icons.check_circle, size: 20, color: c.accent)
                      : Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: c.textFaint,
                        )),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppColors color;
  const _EmptyState({required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppDesign.lg),
    decoration: BoxDecoration(
      borderRadius: AppDesign.radius(AppDesign.rMd),
      border: Border.all(color: color.hairline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.download_for_offline_outlined, color: color.textFaint),
        const SizedBox(width: AppDesign.md),
        Expanded(
          child: Text(
            context.l10n.pickerEmptyHint,
            style: context.text.bodyMuted,
          ),
        ),
      ],
    ),
  );
}
