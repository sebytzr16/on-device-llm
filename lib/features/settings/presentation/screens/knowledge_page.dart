import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../data/local/database/app_database.dart';
import '../../../attachments/data/attachment_store.dart';
import '../../../attachments/domain/scan_options.dart';
import 'scan_settings_page.dart';
import '../../../../data/storage/download_manager.dart';
import '../../../knowledge/knowledge_embedder.dart';
import '../../../knowledge/knowledge_store.dart';
import '../../../knowledge/knowledge_grounding.dart';
import '../../../voice/voice_service.dart';
import '../../../../core/providers/shared_providers.dart';
import '../../../models/domain/entities/model_catalog.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_widgets.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

/// Settings > Knowledge library (FX-02): collections of documents whose
/// passages are retrieved for every question while a collection is active.
class KnowledgePage extends ConsumerStatefulWidget {
  const KnowledgePage({super.key});
  @override
  ConsumerState<KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends ConsumerState<KnowledgePage> {
  bool _importing = false;
  bool _scanCancelled = false;
  String _scanProgress = '';

  Future<String?> _askName(String title, [String initial = '']) => promptText(
    context,
    title: title,
    initial: initial,
    confirmLabel: context.l10n.uiKnowledgePageOK,
    fieldKey: const Key('collection-name'),
  );

  Future<void> _addFiles(String collection) async {
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !mounted) return;
    setState(() => _importing = true);
    _scanCancelled = false;
    final store = ref.read(knowledgeStoreProvider);
    final failures = <String>[];
    for (final f in files) {
      if (_scanCancelled || !mounted) break;
      try {
        if ((await f.length() ?? 0) > AttachmentStore.maxDocumentBytes) {
          throw const FormatException('File is larger than 64 MB.');
        }
        final bytes = await f.readAsBytes();
        if (bytes.length > AttachmentStore.maxDocumentBytes) {
          throw const FormatException('File is larger than 64 MB.');
        }
        await store.import(
          collection: collection,
          name: f.name,
          bytes: bytes,
          cancelled: () => _scanCancelled || !mounted,
          transcribeSegment: (segment) => KnowledgeGrounding.transcript(
            segment,
            ref.read(sherpaVoiceProvider),
            cancelled: () => _scanCancelled || !mounted,
          ),
          caption: (photo) async {
            final model = ref.read(modelManagerProvider).loadedModel;
            if (model == null) return null;
            return KnowledgeGrounding.caption(
              photo,
              ref.read(llamaEngineProvider),
              model.family,
              ref.read(settingsProvider),
              cancelled: () => _scanCancelled || !mounted,
            );
          },
          pdfText: (bytes) => AttachmentStore.pdfText(
            bytes,
            cancelled: () => _scanCancelled || !mounted,
            progress: (page, total) {
              if (mounted) {
                setState(() => _scanProgress = '${f.name} · $page / $total');
              }
            },
          ),
        );
      } on ScanCancelled {
        break;
      } catch (e) {
        failures.add('${f.name}: $e'.replaceFirst('FormatException: ', ''));
      }
    }
    if (mounted) {
      setState(() => _importing = false);
      if (failures.isNotEmpty) {
        showIslandToast(context, failures.join('\n'), tone: IslandTone.error);
      }
      // New passages get vectors right away when the embedding model is here.
      if (ref.read(modelManagerProvider).embeddingReady) {
        unawaited(
          ref.read(knowledgeIndexerProvider.notifier).index(collection),
        );
      }
    }
  }

  /// The semantic-search card: offer the embedding model, show its
  /// download, or report it ready with a way to remove it.
  Widget _embeddingCard(BuildContext context) {
    final c = context.colors;
    final models = ref.watch(modelManagerProvider);
    final manager = ref.read(modelManagerProvider.notifier);
    final progress = models.downloads[ModelManagerState.embeddingKey];
    final status = progress?.status;
    final mb = (embeddingModel.sizeBytes / (1024 * 1024)).round();
    final Widget action;
    if (status == DownloadStatus.downloading ||
        status == DownloadStatus.queued) {
      action = OutlinedButton.icon(
        key: const Key('embedding-pause'),
        onPressed: () => manager.pauseDownload(ModelManagerState.embeddingKey),
        icon: const Icon(Icons.pause, size: 18),
        label: Text('${(progress!.fraction * 100).round()}%'),
      );
    } else if (status == DownloadStatus.verifying) {
      action = OutlinedButton(
        onPressed: null,
        child: Text(context.l10n.uiKnowledgePageVerifying),
      );
    } else if (models.embeddingReady) {
      action = OutlinedButton.icon(
        key: const Key('embedding-remove'),
        onPressed: manager.deleteEmbedding,
        style: OutlinedButton.styleFrom(foregroundColor: c.success),
        icon: const Icon(Icons.check, size: 18),
        label: Text(context.l10n.ready),
      );
    } else {
      action = FilledButton.tonalIcon(
        key: const Key('embedding-add'),
        onPressed: manager.downloadEmbedding,
        icon: Icon(
          status == DownloadStatus.paused || status == DownloadStatus.failed
              ? Icons.refresh
              : Icons.download_outlined,
          size: 18,
        ),
        label: Text(context.l10n.downloadMb(mb)),
      );
    }
    return SettingsGroup(
      children: [
        Padding(
          key: const Key('embedding-card'),
          padding: const EdgeInsets.fromLTRB(
            AppDesign.lg,
            AppDesign.md,
            AppDesign.lg,
            AppDesign.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.hub_outlined, size: 20, color: c.textMuted),
                  const SizedBox(width: AppDesign.sm),
                  Text(context.l10n.searchByMeaning, style: context.text.body),
                ],
              ),
              const SizedBox(height: AppDesign.xs),
              Text(
                models.embeddingReady
                    ? '${embeddingModel.displayName}: passages are also matched by meaning (multilingual), fused with the word index.'
                    : '${embeddingModel.displayName} finds passages that say the same thing in other words, in any language. Runs on the phone; ~$mb MB once.',
                style: context.text.bodyMuted,
              ),
              const SizedBox(height: AppDesign.sm),
              Align(alignment: Alignment.centerRight, child: action),
              if (models.embeddingReady && embeddingModel.projector != null)
                ..._mediaRow(context),
            ],
          ),
        ),
      ],
    );
  }

  /// The optional projector that makes photos and voice notes searchable.
  List<Widget> _mediaRow(BuildContext context) {
    final c = context.colors;
    final models = ref.watch(modelManagerProvider);
    final manager = ref.read(modelManagerProvider.notifier);
    const key = ModelManagerState.embeddingMediaKey;
    final progress = models.downloads[key];
    final status = progress?.status;
    final mb = (embeddingModel.projector!.sizeBytes / (1024 * 1024)).round();
    final Widget action;
    if (status == DownloadStatus.downloading ||
        status == DownloadStatus.queued) {
      action = OutlinedButton.icon(
        key: const Key('embedding-media-pause'),
        onPressed: () => manager.pauseDownload(key),
        icon: const Icon(Icons.pause, size: 18),
        label: Text('${(progress!.fraction * 100).round()}%'),
      );
    } else if (status == DownloadStatus.verifying) {
      action = OutlinedButton(
        onPressed: null,
        child: Text(context.l10n.uiKnowledgePageVerifying),
      );
    } else if (models.embeddingMediaReady) {
      action = OutlinedButton.icon(
        key: const Key('embedding-media-remove'),
        onPressed: manager.deleteEmbeddingMedia,
        style: OutlinedButton.styleFrom(foregroundColor: c.success),
        icon: const Icon(Icons.check, size: 18),
        label: Text(context.l10n.ready),
      );
    } else {
      action = FilledButton.tonalIcon(
        key: const Key('embedding-media-add'),
        onPressed: manager.downloadEmbeddingMedia,
        icon: Icon(
          status == DownloadStatus.paused || status == DownloadStatus.failed
              ? Icons.refresh
              : Icons.download_outlined,
          size: 18,
        ),
        label: Text(context.l10n.downloadMb(mb)),
      );
    }
    return [
      const SizedBox(height: AppDesign.md),
      Row(
        children: [
          Icon(Icons.perm_media_outlined, size: 20, color: c.textMuted),
          const SizedBox(width: AppDesign.sm),
          Text(context.l10n.photosAndVoiceNotes, style: context.text.body),
        ],
      ),
      const SizedBox(height: AppDesign.xs),
      Text(
        models.embeddingMediaReady
            ? context.l10n.photosAndVoiceNotesReady
            : context.l10n.photosAndVoiceNotesBody(mb),
        style: context.text.bodyMuted,
      ),
      const SizedBox(height: AppDesign.sm),
      Align(alignment: Alignment.centerRight, child: action),
    ];
  }

  /// Index progress or the button to (re)build the collection's vectors.
  Widget _indexRow(BuildContext context, String col, int unindexed) {
    final c = context.colors;
    final models = ref.watch(modelManagerProvider);
    final index = ref.watch(knowledgeIndexerProvider);
    final indexer = ref.read(knowledgeIndexerProvider.notifier);
    if (index.running && index.collection == col) {
      return SettingsRow(
        key: Key('kindex-$col'),
        leading: const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text(
          context.l10n.indexingProgress(index.done, index.total),
          style: context.text.bodyMuted,
        ),
        trailing: TextButton(
          onPressed: indexer.cancel,
          child: Text(context.l10n.stop),
        ),
      );
    }
    if (!models.embeddingReady || unindexed == 0) {
      if (index.error != null && index.collection == col) {
        return SettingsRow(
          leading: Icon(Icons.error_outline, color: c.warning),
          title: Text(
            index.error!,
            style: context.text.mono.copyWith(color: c.warning),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    return SettingsRow(
      key: Key('kindex-$col'),
      leading: Icon(Icons.hub_outlined, color: c.accent),
      title: Text(
        context.l10n.indexForMeaning(unindexed),
        style: context.text.body.copyWith(color: c.accent),
      ),
      onTap: index.running ? null : () => indexer.index(col),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final c = context.colors;
    final docs =
        ref.watch(knowledgeDocsProvider).value ?? const <KnowledgeDoc>[];
    final indexed = ref.watch(knowledgeIndexedProvider).value ?? const {};
    final embeddingReady = ref.watch(
      modelManagerProvider.select((m) => m.embeddingReady),
    );
    final collections = {for (final d in docs) d.collection}.toList()..sort();
    if (s.knowledgeCollection.isNotEmpty &&
        !collections.contains(s.knowledgeCollection)) {
      collections.add(s.knowledgeCollection);
    }
    final collectionDocs = {
      for (final col in collections)
        col: docs.where((d) => d.collection == col).toList(),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.knowledgeLibrary),
        actions: [
          IconButton(
            tooltip: context.l10n.scanSettings,
            icon: const Icon(Icons.document_scanner_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ScanSettingsPage()),
            ),
          ),
          IconButton(
            key: const Key('collection-new'),
            tooltip: context.l10n.newCollection,
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () async {
              final name = await _askName(context.l10n.newCollection);
              if (name != null) {
                await n.update(
                  ref
                      .read(settingsProvider)
                      .copyWith(knowledgeCollection: name),
                );
              }
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
                      SettingsNote(
                        context.l10n.knowledgeIntro,
                        icon: Icons.local_library_outlined,
                      ),
                      const SizedBox(height: AppDesign.md),
                      _embeddingCard(context),
                      const SizedBox(height: AppDesign.md),
                      SettingsGroup(
                        children: [
                          SettingsRow(
                            leading: const Icon(Icons.forum_outlined),
                            key: const Key('knowledge-active'),
                            title: Text(context.l10n.useInChats),
                            subtitle: Text(
                              s.knowledgeCollection.isEmpty
                                  ? context.l10n.collectionOff
                                  : context.l10n.collectionActive(
                                      s.knowledgeCollection,
                                    ),
                            ),
                            trailing: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: s.knowledgeCollection,
                                items: [
                                  DropdownMenuItem(
                                    value: '',
                                    child: Text(context.l10n.off),
                                  ),
                                  for (final col in collections)
                                    DropdownMenuItem(
                                      value: col,
                                      child: Text(col),
                                    ),
                                ],
                                onChanged: (v) => v == null
                                    ? null
                                    : n.update(
                                        s.copyWith(knowledgeCollection: v),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_importing)
                        Padding(
                          padding: const EdgeInsets.all(AppDesign.md),
                          child: Row(
                            children: [
                              const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: AppDesign.md),
                              Expanded(
                                child: Text(
                                  _scanProgress.isEmpty
                                      ? context.l10n.readingAndIndexing
                                      : _scanProgress,
                                  style: context.text.bodyMuted,
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => _scanCancelled = true),
                                child: Text(context.l10n.cancel),
                              ),
                            ],
                          ),
                        ),
                      if (collections.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(AppDesign.lg),
                          child: Text(
                            context.l10n.noCollections,
                            style: context.text.bodyMuted,
                          ),
                        ),
                    ],
                  ),
                  for (final col in collections) ...[
                    SliverToBoxAdapter(child: SettingsSection(label: col)),
                    SettingsGroup.sliver(
                      itemCount: collectionDocs[col]!.length + 2,
                      itemBuilder: (context, index) {
                        final documents = collectionDocs[col]!;
                        if (index < documents.length) {
                          final d = documents[index];
                          return Dismissible(
                            key: Key('kdoc-${d.id}'),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: c.danger.fade(0.15),
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(
                                right: AppDesign.lg,
                              ),
                              child: Icon(
                                Icons.delete_outline,
                                color: c.danger,
                              ),
                            ),
                            onDismissed: (_) =>
                                ref.read(knowledgeStoreProvider).remove(d.id),
                            child: SettingsRow(
                              leading: const Icon(Icons.description_outlined),
                              title: Text(d.name),
                              onTap: () => showAppDialog<void>(
                                context: context,
                                builder: (dialog) => AlertDialog(
                                  title: Text(d.name),
                                  content: SingleChildScrollView(
                                    child: SelectableText(
                                      '${d.extractionFormat ?? d.mime}\n${d.sizeBytes} bytes\n${d.chars} characters\n${d.chunkCount} passages\nSHA-256: ${d.contentHash ?? '—'}${d.extractionWarning == null ? '' : '\n\n${d.extractionWarning}'}',
                                    ),
                                  ),
                                  actions: [
                                    if (!d.active)
                                      TextButton(
                                        onPressed: () async {
                                          try {
                                            await ref
                                                .read(knowledgeStoreProvider)
                                                .activate(d);
                                            if (dialog.mounted) {
                                              Navigator.pop(dialog);
                                            }
                                          } catch (e) {
                                            if (dialog.mounted) {
                                              showIslandToast(
                                                dialog,
                                                '$e',
                                                tone: IslandTone.error,
                                              );
                                            }
                                          }
                                        },
                                        child: Text(
                                          context.l10n.restoreVersion,
                                        ),
                                      ),
                                    if (d.originalFile != null)
                                      TextButton(
                                        onPressed: () async {
                                          final missing =
                                              context.l10n.sourceMessageMissing;
                                          try {
                                            final file = await ref
                                                .read(knowledgeStoreProvider)
                                                .original(d);
                                            if (file == null) {
                                              throw StateError(missing);
                                            }
                                            await SharePlus.instance.share(
                                              ShareParams(
                                                files: [
                                                  XFile(
                                                    file.path,
                                                    name: d.name,
                                                    mimeType: d.mime,
                                                  ),
                                                ],
                                              ),
                                            );
                                          } catch (e) {
                                            if (dialog.mounted) {
                                              showIslandToast(
                                                dialog,
                                                '$e',
                                                tone: IslandTone.error,
                                              );
                                            }
                                          }
                                        },
                                        child: Text(context.l10n.originalFile),
                                      ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialog),
                                      child: Text(context.l10n.cancel),
                                    ),
                                  ],
                                ),
                              ),
                              subtitle: Text(
                                '${d.active ? '' : '${context.l10n.previousVersion} · '}'
                                '${d.chunkCount} passages · ${(d.chars / 1000).toStringAsFixed(0)}k characters · ${d.addedAt.toLocal().toString().substring(0, 10)}'
                                '${embeddingReady
                                    ? (indexed[d.id] ?? 0) >= d.chunkCount
                                          ? ' · meaning ✓'
                                          : ' · meaning ${indexed[d.id] ?? 0}/${d.chunkCount}'
                                    : ''}',
                                style: context.text.mono.copyWith(
                                  color: c.textFaint,
                                ),
                              ),
                            ),
                          );
                        }
                        if (index == documents.length) {
                          return _indexRow(
                            context,
                            col,
                            docs
                                .where((d) => d.collection == col)
                                .fold(
                                  0,
                                  (n, d) =>
                                      n +
                                      (d.chunkCount - (indexed[d.id] ?? 0))
                                          .clamp(0, d.chunkCount),
                                ),
                          );
                        }
                        return SettingsRow(
                          key: Key('kadd-$col'),
                          leading: Icon(Icons.add, color: c.accent),
                          title: Text(
                            context.l10n.addFiles,
                            style: context.text.body.copyWith(color: c.accent),
                          ),
                          trailing: IconButton(
                            tooltip: context.l10n.deleteCollection,
                            icon: const Icon(
                              Icons.delete_sweep_outlined,
                              size: 20,
                            ),
                            onPressed: () async {
                              await ref
                                  .read(knowledgeStoreProvider)
                                  .removeCollection(col);
                              if (ref
                                      .read(settingsProvider)
                                      .knowledgeCollection ==
                                  col) {
                                await n.update(
                                  ref
                                      .read(settingsProvider)
                                      .copyWith(knowledgeCollection: ''),
                                );
                              }
                            },
                          ),
                          onTap: _importing ? null : () => _addFiles(col),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
