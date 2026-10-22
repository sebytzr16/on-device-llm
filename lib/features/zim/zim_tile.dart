import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/l10n/l10n.dart';
import '../../core/providers/shared_providers.dart';
import 'zim_wikipedia.dart';
import 'zim_archive.dart';
import '../../core/island/status_island.dart';

/// Settings > Web search: import or remove an offline Wikipedia (a Kiwix
/// .zim file the tester downloaded). The file is copied into the app, read
/// in place, and never sent anywhere.
class ZimTile extends ConsumerStatefulWidget {
  const ZimTile({super.key});
  @override
  ConsumerState<ZimTile> createState() => _ZimTileState();
}

class _ZimTileState extends ConsumerState<ZimTile> {
  String? _progress;

  Future<String> _target() async =>
      ZimWikipedia.fileIn((await getApplicationSupportDirectory()).path);

  Future<void> _import() async {
    final toast = islandToastFor(context);
    final notZim = context.l10n.zimNotAZim;
    final files = await FilePicker.pickFiles(type: FileType.any);
    if (files.isEmpty || !mounted) return;
    final f = files.first;
    final target = await _target();
    final part = File('$target.part');
    try {
      await part.parent.create(recursive: true);
      final total = await f.length() ?? 0;
      var done = 0;
      final sink = part.openWrite();
      await for (final chunk in f.readAsByteStream()) {
        sink.add(chunk);
        done += chunk.length;
        final shown = total > 0 ? '${(100 * done / total).floor()} %' : null;
        if (mounted && shown != null && shown != _progress) {
          setState(() => _progress = shown);
        }
      }
      await sink.close();
      if (!await ZimWikipedia.isZim(part.path)) {
        await part.delete();
        toast(notZim, tone: IslandTone.warning);
        return;
      }
      // Validate tables and modern/legacy listings before replacing a
      // working archive. Magic bytes alone do not establish readability.
      final checked = await ZimArchive.open(part.path);
      try {
        await checked.metadata('Date');
      } finally {
        await checked.close();
      }
      await (await ref.read(zimWikipediaProvider.future))?.close();
      await part.rename(target);
      ref.invalidate(zimWikipediaProvider);
    } catch (e) {
      if (await part.exists()) await part.delete();
      toast('$e', tone: IslandTone.error);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  Future<void> _remove() async {
    await (await ref.read(zimWikipediaProvider.future))?.close();
    final f = File(await _target());
    if (await f.exists()) await f.delete();
    ref.invalidate(zimWikipediaProvider);
  }

  @override
  Widget build(BuildContext context) {
    final zim = ref.watch(zimWikipediaProvider).value;
    return ListTile(
      key: const Key('zim-wikipedia'),
      title: Text(context.l10n.zimSetting),
      subtitle: _progress != null
          ? Text(context.l10n.zimImporting(_progress!))
          : zim == null
          ? Text(context.l10n.zimHint)
          : FutureBuilder<String>(
              future: zim.name(),
              builder: (_, s) => Text(s.data ?? '…'),
            ),
      trailing: _progress != null
          ? null
          : TextButton(
              key: const Key('zim-action'),
              onPressed: zim == null ? _import : _remove,
              child: Text(
                zim == null ? context.l10n.zimImport : context.l10n.zimRemove,
              ),
            ),
    );
  }
}
