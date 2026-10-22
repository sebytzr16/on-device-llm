import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/l10n/l10n.dart';
import '../../core/providers/shared_providers.dart';
import '../../data/network/web_search/search_models.dart';
import '../../core/design/app_design.dart';

/// Local article links stay inside the imported archive. The saved excerpt
/// remains available if that archive has since been replaced or removed.
class ZimArticlePage extends ConsumerWidget {
  final String url, title, excerpt;
  final String? archiveDate, archiveId;
  const ZimArticlePage({
    super.key,
    required this.url,
    required this.title,
    required this.excerpt,
    this.archiveDate,
    this.archiveId,
  });
  Future<SearchResult?> _article(WidgetRef ref) async {
    final wiki = await ref.read(zimWikipediaProvider.future);
    if (wiki == null || archiveId == null) return null;
    if (await wiki.archiveIdentity() != archiveId) return null;
    final date = await wiki.archiveMetadata('Date');
    if (date != archiveDate) return null;
    final name = Uri.decodeComponent(url.substring(6)).replaceAll('_', ' ');
    return wiki.article(name);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: FutureBuilder<SearchResult?>(
      future: _article(ref),
      builder: (context, s) {
        if (s.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(AppDesign.lg),
          children: [
            Text(
              context.l10n.sourceArchiveSnapshot(
                archiveDate ?? '—',
                s.data?.archiveLanguage ?? '—',
              ),
            ),
            Text(context.l10n.sourceOfflineLimitation),
            if (s.data == null) Text(context.l10n.sourceArchiveUnavailable),
            const SizedBox(height: AppDesign.lg),
            SelectableText(s.data?.pageText ?? excerpt),
          ],
        );
      },
    ),
  );
}
