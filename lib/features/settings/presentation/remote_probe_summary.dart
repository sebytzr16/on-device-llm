import '../../../l10n/app_localizations.dart';
import '../../../inference/remote/remote_engine.dart';

String remoteProbeSummary(AppLocalizations t, RemoteServerReport report) {
  final base = t.remoteProbeModels(report.models.length);
  if (report.health == 'n/a') return base;
  final health = switch (report.health) {
    'not advertised' => t.remoteProbeNotAdvertised,
    'unknown' => t.remoteProbeUnknown,
    'ok' => t.remoteProbeOk,
    _ => report.health,
  };
  final tools = report.tools.isEmpty
      ? t.remoteProbeNoTools
      : t.remoteProbeTools(report.tools.length);
  return '$base · ${t.remoteProbeHealth(health)} · $tools';
}
