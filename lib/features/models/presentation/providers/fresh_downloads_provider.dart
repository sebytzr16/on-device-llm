import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/model_categories.dart';
import 'model_manager_provider.dart';

/// Chat models whose download finished in this session (first-run guide,
/// owner 2026-11-16): the Models page offers to load them. A model leaves
/// the set once it has been loaded. Watch it from the app root so a
/// download that ends on another page is still noticed.
class FreshDownloads extends Notifier<Set<String>> {
  /// Every model seen downloading: the catalog row may turn downloaded
  /// before or after its progress entry goes away.
  final _downloading = <String>{};

  @override
  Set<String> build() {
    ref.listen(modelManagerProvider, (previous, next) {
      _downloading.addAll(next.downloads.keys);
      if (previous == null) return;
      final before = {
        for (final m in previous.catalog)
          if (m.isDownloaded) m.id,
      };
      final added = {
        for (final m in next.catalog)
          if (m.isDownloaded &&
              !before.contains(m.id) &&
              _downloading.contains(m.id) &&
              modelCategory(m.fileName) == ModelCategory.llm)
            m.id,
      };
      final loaded = next.loadedModelId;
      final kept = {...state, ...added}..remove(loaded);
      if (kept.length != state.length || !kept.containsAll(state)) {
        state = kept;
      }
    });
    return const {};
  }
}

final freshDownloadsProvider = NotifierProvider<FreshDownloads, Set<String>>(
  FreshDownloads.new,
);
