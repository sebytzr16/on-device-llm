import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../chat/presentation/screens/message_source_page.dart';

import '../../../../core/design/app_design.dart';
import '../../../../data/local/database/app_database.dart';
import '../../../memory/domain/user_memory.dart';
import '../../../memory/presentation/providers/memory_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_widgets.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

/// Settings > Memory: the switch, everything the app has learned about the
/// user, and the means to correct or wipe it. All local.
class MemoryPage extends ConsumerWidget {
  const MemoryPage({super.key});

  Future<void> _editDialog(
    BuildContext context,
    WidgetRef ref, {
    Memory? existing,
  }) async {
    final text = await promptText(
      context,
      title: existing == null
          ? context.l10n.addMemory
          : context.l10n.editMemory,
      initial: existing?.content ?? '',
      hint: context.l10n.uiMemoryPageEGTheUserIsA,
      confirmLabel: context.l10n.save,
      maxLines: 4,
      maxLength: UserMemory.maxFactLength,
      selectAll: false,
    );
    if (text == null || text.trim().length < UserMemory.minFactLength) return;
    final store = ref.read(memoryStoreProvider);
    if (existing == null) {
      await store.add(text);
    } else {
      await store.edit(existing, text);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final memories = ref.watch(memoriesProvider).value ?? const <Memory>[];
    final remote = s.usesRemote ? s.activeRemoteProfile : null;
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.memory),
        actions: [
          IconButton(
            key: const Key('memory-add'),
            tooltip: context.l10n.addMemory,
            icon: const Icon(Icons.add),
            onPressed: () => _editDialog(context, ref),
          ),
          IconButton(
            key: const Key('memory-scan-history'),
            tooltip: context.l10n.memoryScanHistory,
            icon: const Icon(Icons.manage_search),
            onPressed: !s.memoryEnabled
                ? null
                : () async {
                    final count = await ref
                        .read(memoryStoreProvider)
                        .scanSavedChats(
                          enabled: () =>
                              context.mounted &&
                              ref.read(settingsProvider).memoryEnabled,
                        );
                    if (context.mounted) {
                      showIslandToast(
                        context,
                        context.l10n.memoryScanResult(count),
                        tone: IslandTone.done,
                      );
                    }
                  },
          ),
          if (memories.isNotEmpty)
            IconButton(
              key: const Key('memory-clear'),
              tooltip: context.l10n.forgetEverything,
              icon: const Icon(Icons.delete_sweep_outlined),
              onPressed: () async {
                final ok = await confirmAction(
                  context,
                  title: context.l10n.forgetEverythingQuestion,
                  message: context.l10n.forgetEverythingHint(memories.length),
                  confirmLabel: context.l10n.forget,
                  destructive: true,
                );
                if (ok == true) await ref.read(memoryStoreProvider).clear();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppDesign.lg,
                AppDesign.sm,
                AppDesign.lg,
                AppDesign.xxl,
              ),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverList.list(
                    children: [
                      SettingsGroup(
                        children: [
                          SettingsSwitchRow(
                            secondary: const Icon(Icons.person_outline_rounded),
                            key: const Key('memory-enabled'),
                            title: Text(context.l10n.rememberAboutMe),
                            subtitle: Text(context.l10n.rememberAboutMeHint),
                            value: s.memoryEnabled,
                            onChanged: (v) =>
                                n.update(s.copyWith(memoryEnabled: v)),
                          ),
                        ],
                      ),
                      SettingsNote(
                        context.l10n.memoryStorageHint,
                        icon: Icons.lock_outline,
                      ),
                      if (remote != null) ...[
                        SettingsSection(label: remote.name),
                        SettingsNote(context.l10n.memoryRemoteLocalHint),
                        SettingsGroup(
                          children: [
                            SettingsSwitchRow(
                              secondary: const Icon(Icons.ios_share_rounded),
                              key: const Key('memory-remote-share'),
                              title: Text(context.l10n.remoteShareMemory),
                              subtitle: Text(
                                context.l10n.remoteShareMemoryHint,
                              ),
                              value: remote.shareMemory,
                              onChanged: (v) => n.update(
                                s.copyWith(
                                  remoteProfiles: [
                                    for (final p in s.remoteProfiles)
                                      p.id == remote.id
                                          ? p.copyWith(
                                              shareMemory: v,
                                              learnMemory: v && p.learnMemory,
                                            )
                                          : p,
                                  ],
                                ),
                              ),
                            ),
                            SettingsSwitchRow(
                              secondary: const Icon(Icons.school_outlined),
                              key: const Key('memory-remote-learn'),
                              title: Text(context.l10n.remoteLearnMemory),
                              subtitle: Text(
                                context.l10n.remoteLearnMemoryHint,
                              ),
                              value: remote.learnMemory,
                              onChanged: remote.shareMemory
                                  ? (v) => n.update(
                                      s.copyWith(
                                        remoteProfiles: [
                                          for (final p in s.remoteProfiles)
                                            p.id == remote.id
                                                ? p.copyWith(learnMemory: v)
                                                : p,
                                        ],
                                      ),
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ],
                      SettingsSection(
                        label: context.l10n.whatAssistantRemembers,
                      ),
                    ],
                  ),
                  if (memories.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(AppDesign.lg),
                        child: Text(
                          s.memoryEnabled
                              ? context.l10n.nothingYetFills
                              : context.l10n.nothingStoredSwitch,
                          style: context.text.bodyMuted,
                        ),
                      ),
                    )
                  else
                    SettingsGroup.sliver(
                      itemCount: memories.length,
                      itemBuilder: (context, index) {
                        final m = memories[index];
                        return Dismissible(
                          key: Key('memory-${m.id}'),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: c.danger.fade(0.15),
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: AppDesign.lg),
                            child: Icon(Icons.delete_outline, color: c.danger),
                          ),
                          onDismissed: (_) =>
                              ref.read(memoryStoreProvider).remove(m.id),
                          child: SettingsRow(
                            title: Text(m.content),
                            subtitle: Text(
                              '${m.sourceChatId == null ? 'added by you' : 'learned'} · ${m.updatedAt.toLocal().toString().substring(0, 10)}'
                              // A note about a moment (where the user was that
                              // day) is kept but never shown to the model; say so
                              // rather than let it look like it is in use.
                              '${UserMemory.transient(m.content) ? ' · passing state, not given to the model' : ''}'
                              '${m.expiresAt == null ? '' : '\n${context.l10n.memoryExpires(m.expiresAt!.toLocal().toString().substring(0, 10))}'}',
                              style: context.text.mono.copyWith(
                                color: UserMemory.transient(m.content)
                                    ? c.warning
                                    : c.textFaint,
                              ),
                            ),
                            onTap: () => _editDialog(context, ref, existing: m),
                            isThreeLine: m.expiresAt != null,
                            trailing: PopupMenuButton<String>(
                              icon: Icon(
                                m.pinned ? Icons.push_pin : Icons.more_vert,
                              ),
                              onSelected: (action) async {
                                final store = ref.read(memoryStoreProvider);
                                switch (action) {
                                  case 'source':
                                    if (m.sourceChatId != null &&
                                        m.sourceMessageId != null) {
                                      unawaited(
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute<void>(
                                            builder: (_) => MessageSourcePage(
                                              chatId: m.sourceChatId!,
                                              messageId: m.sourceMessageId!,
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                  case 'pin':
                                    await store.pin(m, !m.pinned);
                                  case 'confirm':
                                    await store.edit(m, m.content);
                                  case 'expire':
                                    await store.expire(
                                      m,
                                      m.expiresAt == null
                                          ? DateTime.now().add(
                                              const Duration(days: 30),
                                            )
                                          : null,
                                    );
                                }
                              },
                              itemBuilder: (_) => [
                                if (m.sourceChatId != null &&
                                    m.sourceMessageId != null)
                                  PopupMenuItem(
                                    value: 'source',
                                    child: Text(context.l10n.sourceMessage),
                                  ),
                                PopupMenuItem(
                                  value: 'pin',
                                  child: Text(
                                    m.pinned
                                        ? context.l10n.memoryUnpin
                                        : context.l10n.memoryPin,
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'confirm',
                                  child: Text(context.l10n.memoryReconfirm),
                                ),
                                PopupMenuItem(
                                  value: 'expire',
                                  child: Text(
                                    m.expiresAt == null
                                        ? context.l10n.memoryExpire
                                        : context.l10n.memoryNoExpiry,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
