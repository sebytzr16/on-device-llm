import '../../../../core/l10n/l10n.dart';

String _ms(num value) => '${value.round()} ms';

/// Lifecycle timestamps are cumulative from send, including tool rounds.
List<(String, String)> runTimingRows(
  AppLocalizations t,
  Map<String, dynamic> metrics,
) {
  final rows = <(String, String)>[];
  final lifecycle = metrics['lifecycle'];
  if (lifecycle is List) {
    bool prepared = false, preparationShown = false, writingShown = false;
    for (final event in lifecycle) {
      if (event is! Map) continue;
      final stage = event['stage'], elapsed = event['elapsedMs'];
      if (stage == 'preparing') prepared = true;
      if (elapsed is! num || !elapsed.isFinite) continue;
      if (prepared &&
          !preparationShown &&
          (stage == 'reading' || stage == 'researching')) {
        rows.add((t.runAppPreparation, _ms(elapsed)));
        preparationShown = true;
      }
      if (!writingShown && stage == 'writing') {
        rows.add((t.runSendToFirstText, _ms(elapsed)));
        writingShown = true;
      }
    }
  }
  for (final (key, label) in [
    ('beginMs', t.runPromptSetup),
    ('prefillMs', t.runPromptReading),
    ('checkpointMs', t.runCheckpoints),
  ]) {
    final value = metrics[key];
    if (value is! num || !value.isFinite) continue;
    var formatted = _ms(value);
    final prompt = metrics['promptTokens'],
        cached = metrics['cachedPromptTokens'];
    if (key == 'prefillMs' &&
        value > 0 &&
        prompt is num &&
        prompt.isFinite &&
        (cached == null || cached is num && cached.isFinite)) {
      final tokens = prompt - (cached as num? ?? 0);
      if (tokens >= 0) {
        formatted += ' · ${(tokens * 1000 / value).toStringAsFixed(1)} tok/s';
      }
    }
    rows.add((label, formatted));
  }
  if (metrics['requestMs'] case final num ms when ms.isFinite) {
    rows.add((t.runProviderAnswered, _ms(ms)));
  }
  if (metrics['providerWaits'] case final List waits when waits.isNotEmpty) {
    rows.add((
      t.runProviderBusy,
      [
        for (final w in waits)
          if (w case {'status': final num status, 'waitMs': final num ms})
            t.runProviderWait(status.toInt(), (ms / 1000).round()),
      ].join('; '),
    ));
  }
  return rows;
}

List<(String, String)> engineTimingRows(
  AppLocalizations t,
  Map<String, dynamic> engine,
) => [
  if (engine['warmupMs'] case final num ms when ms.isFinite)
    (t.runWarmup, _ms(ms)),
  if (engine['projectorDevice'] == 'gpu') (t.projectorDevice, t.projectorGpu),
  if (engine['projectorDevice'] == 'cpu') (t.projectorDevice, t.projectorCpu),
];
