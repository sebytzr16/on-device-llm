import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_dialog.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/island/status_island.dart';
import '../../../../data/storage/download_history.dart';
import '../../../../data/storage/download_manager.dart';
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
    final active = ref
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
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.l10n;
    final state = ref.watch(modelManagerProvider);
    final active = state.downloads.values.where(activeDownload).toList();
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
              if (active.isEmpty)
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
              history.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('$e'),
                data: (rows) => Column(
                  children: [
                    if (rows.isEmpty) Text(t.modelNoHistory),
                    for (final row in rows.where(
                      (r) => !active.any(
                        (p) =>
                            p.modelId == r.modelId && r.result == 'interrupted',
                      ),
                    ))
                      ListTile(
                        title: Text(row.name),
                        subtitle: Text(
                          '${bytesLabel(row.size)} · ${MaterialLocalizations.of(context).formatMediumDate(row.date.toLocal())}',
                        ),
                        trailing: Text(result(row.result)),
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
