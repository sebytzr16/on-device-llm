import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/island/status_island.dart';
import '../../../../data/storage/download_history.dart';
import '../../../../data/storage/download_manager.dart';
import '../../../image_gen/image_gen_downloads.dart';
import '../../../image_gen/image_gen_imports.dart';
import '../../../image_gen/image_gen_model_widgets.dart';
import '../providers/model_manager_provider.dart';
import 'model_tags.dart';

bool activeDownload(DownloadProgress p) => const {
  DownloadStatus.queued,
  DownloadStatus.downloading,
  DownloadStatus.verifying,
}.contains(p.status);

final downloadHistoryProvider = StreamProvider<List<DownloadRecord>>((ref) {
  final controller = StreamController<List<DownloadRecord>>();
  Future<void> update() async {
    try {
      final rows = await DownloadHistory.read();
      if (!controller.isClosed) controller.add(rows);
    } catch (e, s) {
      if (!controller.isClosed) controller.addError(e, s);
    }
  }

  final sub = DownloadHistory.changes.stream.listen((_) => update());
  unawaited(update());
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(controller.close());
  });
  return controller.stream;
});

class DownloadsButton extends ConsumerWidget {
  final bool onlyWhenActive;

  /// A labelled button beside "Import GGUF" on the PC (owner 2026-11-01);
  /// the phone keeps the icon.
  final bool labelled;
  const DownloadsButton({
    super.key,
    this.onlyWhenActive = false,
    this.labelled = false,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final imageActive = ref
        .watch(imageGenDownloadsProvider)
        .models
        .values
        .where((m) => m.status == ImageGenModelStatus.downloading)
        .length;
    final active =
        imageActive +
        ref
            .watch(modelManagerProvider)
            .downloads
            .values
            .where(activeDownload)
            .length;
    if (onlyWhenActive && active == 0) return const SizedBox.shrink();
    final icon = Badge(
      isLabelVisible: active > 0,
      label: Text('$active'),
      child: Icon(Icons.downloading_outlined, size: labelled ? 18 : null),
    );
    void open() => showAppDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        child: SizedBox(
          width: 640,
          height: 560,
          child: Padding(padding: EdgeInsets.all(20), child: DownloadCenter()),
        ),
      ),
    );
    if (labelled) {
      return FilledButton.tonalIcon(
        style: appTonalButtonStyle(context),
        key: const Key('model-downloads-button'),
        onPressed: open,
        icon: icon,
        label: Text(context.l10n.modelDownloads),
      );
    }
    return IconButton(
      key: const Key('model-downloads-button'),
      tooltip: context.l10n.modelDownloads,
      icon: icon,
      onPressed: open,
    );
  }
}

class DownloadCenter extends ConsumerWidget {
  const DownloadCenter({super.key});
  Future<void> _remove(BuildContext context, {DownloadRecord? row}) async {
    final t = context.l10n;
    final clear = row == null;
    if (!await confirmAction(
      context,
      title: clear
          ? t.downloadClearFinishedHistory
          : t.downloadRemoveHistoryRow,
      message: clear
          ? t.downloadClearFinishedConfirm
          : t.downloadRemoveHistoryConfirm(row.name),
      confirmLabel: clear
          ? t.downloadClearFinishedHistory
          : t.downloadRemoveHistoryRow,
      destructive: true,
    )) {
      return;
    }
    try {
      if (clear) {
        await DownloadHistory.clearFinished();
      } else {
        await DownloadHistory.remove(row.attempt);
      }
    } catch (_) {
      if (context.mounted) {
        showIslandToast(context, t.historyRemoveError, tone: IslandTone.error);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final state = ref.watch(modelManagerProvider);
    final active = state.downloads.values.where(activeDownload).toList();
    final imageState = ref.watch(imageGenDownloadsProvider);
    final imageModels = imageGenManagedModels(
      ref.watch(imageGenImportsProvider),
    );
    final imageActive = imageModels.where((m) {
      final s = imageState.of(m);
      return s.status == ImageGenModelStatus.downloading ||
          s.status != ImageGenModelStatus.ready && s.paused;
    }).toList();
    final history = ref.watch(downloadHistoryProvider);
    String nameFor(DownloadProgress p) {
      final id = p.modelId.replaceFirst(RegExp(r':vision$'), '');
      return state.catalog.where((m) => m.id == id).firstOrNull?.displayName ??
          p.modelId;
    }

    String result(String value) => switch (value) {
      'completed' => t.modelDownloadCompleted,
      'failed' => t.modelDownloadFailed,
      'paused' => t.modelDownloadPaused,
      'cancelled' => t.modelDownloadCancelled,
      _ => t.modelDownloadInterrupted,
    };
    String historyResult(DownloadRecord row) {
      final model = imageGenModelForDownload(
        row.modelId,
        ref.read(imageGenImportsProvider),
      );
      final label = result(row.result);
      if (model == null) return label;
      final percent = row.result == 'completed'
          ? 100.0
          : (imageState.of(model).received / model.sizeBytes * 100).clamp(
              0.0,
              100.0,
            );
      return '$label \u00b7 ${percent.toStringAsFixed(1)}%';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(t.modelDownloads, style: context.text.title)),
            IconButton(
              tooltip: t.desktopClose,
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            children: [
              for (final model in imageActive)
                ImageGenDownloadRow(model: model),
              if (active.isEmpty && imageActive.isEmpty)
                Text(t.modelNoDownloads, style: context.text.small),
              for (final p in active)
                ListTile(
                  title: Text(nameFor(p)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: p.status == DownloadStatus.verifying
                            ? null
                            : p.fraction,
                      ),
                      Text(
                        p.status == DownloadStatus.verifying
                            ? t.verifyingSha
                            : '${bytesLabel(p.received)} / ${bytesLabel(p.total)}',
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: t.cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    onPressed: () async {
                      try {
                        await ref
                            .read(modelManagerProvider.notifier)
                            .cancelDownload(p.modelId);
                      } catch (e) {
                        if (context.mounted) {
                          showIslandToast(
                            context,
                            '$e',
                            tone: IslandTone.error,
                          );
                        }
                      }
                    },
                  ),
                ),
              const SizedBox(height: 24),
              Text(t.modelDownloadHistory, style: context.text.title),
              Text(
                t.downloadHistoryHint,
                style: context.text.caption.copyWith(
                  color: context.colors.textMuted,
                ),
              ),
              history.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (rows) => Column(
                  children: [
                    if (rows.isEmpty) Text(t.modelNoHistory),
                    if (rows.any(DownloadHistory.isFinished))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => _remove(context),
                          child: Text(t.downloadClearFinishedHistory),
                        ),
                      ),
                    for (final row in rows.where(
                      (r) => !active.any(
                        (p) =>
                            p.modelId == r.modelId && r.result == 'interrupted',
                      ),
                    ))
                      ListTile(
                        title: Text(row.name),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(historyResult(row)),
                            Text(
                              '${bytesLabel(row.size)} · ${MaterialLocalizations.of(context).formatMediumDate(row.date.toLocal())}',
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (row.result != 'completed' &&
                                imageGenModelForDownload(
                                      row.modelId,
                                      ref.read(imageGenImportsProvider),
                                    ) !=
                                    null)
                              IconButton(
                                tooltip: t.imageResumeDownload,
                                icon: const Icon(Icons.play_arrow),
                                onPressed: () => ref
                                    .read(imageGenDownloadsProvider.notifier)
                                    .download(
                                      imageGenModelForDownload(
                                        row.modelId,
                                        ref.read(imageGenImportsProvider),
                                      )!,
                                    ),
                              ),
                            IconButton(
                              tooltip: t.downloadRemoveHistoryRow,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _remove(context, row: row),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
