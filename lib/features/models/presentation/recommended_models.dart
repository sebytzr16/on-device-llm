import '../domain/entities/model_catalog.dart';
import '../domain/entities/model_info.dart';
import '../domain/entities/model_suggestions.dart';
import 'widgets/model_tags.dart';

/// "Recommended" order for models that are not downloaded yet, ranked by the
/// hardware this device reports (owner 2026-11-12).
///
/// Models that fit come first, then tight fits, then unknown. A model too
/// large for this device is not recommended at all (a phone listed
/// Qwen3.5 9B as "Too large for this device", 2026-11-16); search and
/// Discover still find it.
/// Within a group, curated picks come before other entries, and the larger
/// model comes first: a bigger model that still fits answers better. The
/// order works for any device; nothing is tuned to one machine.
List<ModelInfo> rankRecommended(
  Iterable<ModelInfo> models, {
  required ModelFit Function(ModelInfo) fit,
  required bool desktop,
}) {
  int group(ModelInfo m) => switch (fit(m)) {
    ModelFit.fits => 0,
    ModelFit.tight => 1,
    ModelFit.unknown => 2,
    ModelFit.tooLarge => 3,
  };
  double size(ModelInfo m) =>
      catalogMeta[m.id]?.parameterCountB ??
      m.parameterCountB?.toDouble() ??
      m.sizeBytes / 1e9;
  final indexed = models
      .where((m) => fit(m) != ModelFit.tooLarge)
      .indexed
      .toList();
  indexed.sort((a, b) {
    final (ia, ma) = a;
    final (ib, mb) = b;
    final g = group(ma).compareTo(group(mb));
    if (g != 0) return g;
    final ca = modelSuggestionRank(ma, desktop: desktop) == null ? 1 : 0;
    final cb = modelSuggestionRank(mb, desktop: desktop) == null ? 1 : 0;
    if (ca != cb) return ca.compareTo(cb);
    final s = size(mb).compareTo(size(ma));
    return s != 0 ? s : ia.compareTo(ib);
  });
  return [for (final (_, m) in indexed) m];
}

/// The model to suggest first (first-run guide, owner 2026-11-16): the top
/// of [rankRecommended] when it fits this device, otherwise none, so the
/// guide never suggests a model that would not load well.
ModelInfo? bestFitModel(
  Iterable<ModelInfo> models, {
  required ModelFit Function(ModelInfo) fit,
  required bool desktop,
}) {
  final ranked = rankRecommended(models, fit: fit, desktop: desktop);
  final top = ranked.firstOrNull;
  return top != null && fit(top) == ModelFit.fits ? top : null;
}
