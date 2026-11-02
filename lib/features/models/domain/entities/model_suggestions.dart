import 'model_catalog.dart';
import 'model_info.dart';

/// Only the curated picks are suggested. Catalog identities and pinned files stay intact.
int? modelSuggestionRank(ModelInfo model, {required bool desktop}) {
  final name = '${model.id} ${model.displayName}'.toLowerCase().replaceAll(
    RegExp(r'[^a-z0-9.]'),
    '',
  );
  if (name.contains('qwen36') && name.contains('35b')) {
    return desktop ? 6 : null;
  }
  if (name.contains('qwen35') || name.contains('qwen3.5')) {
    if (name.contains('0.8b')) return 0;
    if (name.contains('4b') && !name.contains('e4b')) return 1;
    if (name.contains('9b')) return 2;
    if (desktop && RegExp(r'35b').hasMatch(name)) return 6;
  }
  if (name.contains('gemma4') && name.contains('e2b')) return 3;
  if (name.contains('gemma4') && name.contains('e4b')) return 4;
  if (name.contains('lfm3')) return 5;
  return null;
}

List<ModelInfo> suggestedModels(
  Iterable<ModelInfo> library, {
  required bool desktop,
}) {
  final entries = <String, ModelInfo>{
    for (final model in [...bundledCatalog, ...desktopCatalog, ...library])
      model.id: model,
  };
  return entries.values
      .where(
        (m) =>
            !m.isDownloaded && modelSuggestionRank(m, desktop: desktop) != null,
      )
      .toList()
    ..sort(
      (a, b) => modelSuggestionRank(
        a,
        desktop: desktop,
      )!.compareTo(modelSuggestionRank(b, desktop: desktop)!),
    );
}

List<ModelInfo> availableLibraryModels(
  Iterable<ModelInfo> library, {
  required bool desktop,
}) {
  final known = {...bundledCatalog, ...desktopCatalog}.map((m) => m.id).toSet();
  return [
    ...library.where(
      (m) =>
          !m.isDownloaded &&
          !known.contains(m.id) &&
          modelSuggestionRank(m, desktop: desktop) == null,
    ),
    ...suggestedModels(library, desktop: desktop),
  ];
}
