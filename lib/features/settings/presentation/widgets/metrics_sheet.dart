import '../../../../desktop/engine_files_panel.dart';
import '../../../../core/l10n/cpu_variant_labels.dart';
import '../../../../core/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../core/design/app_sheet.dart';
import '../../../../core/platform/device_info.dart';
import '../../../../core/platform/desktop_host.dart';
import '../../../benchmark/benchmark.dart';
import '../../../benchmark/benchmark_dialog.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../models/domain/entities/model_info.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../../../core/motion/motion.dart';

/// Live instrument panel: what the engine measured on the last turn.
/// Reads chatProvider.metrics (engine info JSON) and the loaded model.
Future<void> showMetricsSheet(BuildContext context) => showMorphSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => const _MetricsSheet(),
);

const _cpuFallbackPrefix = 'CPU (GPU unavailable';
const _cpuNotAutoPrefix = 'CPU (';

class _MetricsSheet extends ConsumerWidget {
  const _MetricsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final metrics = ref.watch(chatProvider.select((s) => s.metrics));
    final model = ref.watch(modelManagerProvider.select((s) => s.loadedModel));
    final choice = ref.read(modelManagerProvider.notifier).backendChoice;
    final hz = ref.watch(displayRefreshRateProvider).value ?? 0;

    return AppSheet(
      title: context.l10n.uiMetricsSheetInstrumentPanel,
      primary: model == null
          ? null
          : FilledButton.icon(
              key: const Key('panel-benchmark'),
              onPressed: ref.watch(chatProvider.select((s) => s.isGenerating))
                  ? null
                  : () =>
                        showBenchmarkDialog(context, ref, model, runNow: true),
              icon: const Icon(Icons.speed_outlined, size: 16),
              label: Text(context.l10n.uiMetricsSheetBenchmarkThisModel),
            ),
      children: [
        if (metrics.isEmpty)
          _Empty(model: model)
        else
          _Panel(metrics: metrics, model: model, choice: choice),
        if (hz > 0)
          _Row(
            label: context.l10n.uiMetricsSheetDisplay,
            value: '${hz.round()} Hz',
            detail: hz < 90 && !DesktopHost.active
                ? context.l10n.displayHzPhoneLimited(hz.round())
                : null,
            tone: hz < 90 && !DesktopHost.active ? c.warning : null,
          ),
        if (model != null)
          if (ref.watch(benchmarkProvider).results[model.id] case final r?)
            Padding(
              padding: EdgeInsets.zero,
              child: Text(
                context.l10n.metricsLastBenchmark(
                  r.decodeTps.toStringAsFixed(1),
                  r.prefillTps.toStringAsFixed(0),
                  r.backend,
                ),
                style: context.text.mono.copyWith(color: c.textMuted),
              ),
            ),
        if (DesktopHost.active) const EngineFilesPanel(),
        const SizedBox(height: AppDesign.xl),
        Row(
          children: [
            Icon(Icons.lock_outline, size: 13, color: c.textFaint),
            const SizedBox(width: AppDesign.sm),
            Expanded(
              child: Text(
                context.l10n.uiMetricsSheetMeasuredOnThisDeviceNothingIs,
                style: context.text.mono.copyWith(color: c.textFaint),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final ModelInfo? model;
  const _Empty({required this.model});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            vertical: AppDesign.xxl,
            horizontal: AppDesign.lg,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: c.hairline),
            borderRadius: AppDesign.radius(AppDesign.rLg),
          ),
          child: Column(
            children: [
              Icon(Icons.speed_outlined, size: 28, color: c.textFaint),
              const SizedBox(height: AppDesign.md),
              Text(
                context.l10n.uiMetricsSheetSendAMessageToSeeLive,
                style: context.text.bodyMuted,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        if (model != null) ...[
          const SizedBox(height: AppDesign.lg),
          _ModelRow(model: model),
        ],
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Map<String, dynamic> metrics;
  final ModelInfo? model;
  final String? choice;
  const _Panel({required this.metrics, required this.model, this.choice});

  num? _n(String key) => metrics[key] is num ? metrics[key] as num : null;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final backend = metrics['backend']?.toString() ?? '—';
    final fallback = backend.startsWith(_cpuFallbackPrefix);
    // "CPU (<GPU> available, not auto-selected)": informational, not a failure.
    final notAuto = !fallback && backend.startsWith(_cpuNotAutoPrefix);
    // ABI 3+ sends the structured reason; older strings carry it in the label.
    final structured = metrics['fallbackReason']?.toString() ?? '';
    final reason = structured.isNotEmpty
        ? structured
        : fallback
        ? backend
              .substring(_cpuFallbackPrefix.length)
              .replaceFirst(RegExp(r'^:\s*'), '')
              .replaceFirst(RegExp(r'\)$'), '')
        : null;

    final tps = _n('tokensPerSecond');
    final firstMs = _n('firstTokenMs');
    final tokens = _n('tokens');
    final prompt = _n('promptTokens');
    final used = _n('contextUsed');
    final size = _n('contextSize');
    final rss = _n('peakRssMb');
    final trimmed = _n('trimmedMessages') ?? 0;
    final fill = (used != null && size != null && size > 0)
        ? (used / size).clamp(0.0, 1.0)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Row(
          label: context.l10n.uiMetricsSheetBackend,
          value: fallback || notAuto ? 'CPU' : backend,
          tone: fallback ? c.warning : null,
          detail: fallback
              ? context.l10n.metricsGpuUnavailable(
                  reason!.isEmpty ? context.l10n.metricsUnknownReason : reason,
                )
              : notAuto
              ? reason
              : choice,
        ),
        if (metrics['nativeLibrary'] != null)
          _Row(
            label: context.l10n.uiMetricsSheetNativeLibrary,
            value: metrics['nativeLibrary']
                .toString()
                .replaceFirst(RegExp(r'^lib'), '')
                .replaceFirst(RegExp(r'\.so$'), ''),
            detail:
                cpuVariantFallback(context.l10n, metrics) ??
                ((metrics['nativeLibrarySkipped'] as List?)?.isNotEmpty == true
                    ? context.l10n.metricsGpuVariantUnavailable(
                        (metrics['nativeLibrarySkipped'] as List).first
                            .toString()
                            .split(': ')
                            .last,
                      )
                    : null),
          ),
        if (metrics['stages'] is Map)
          _Row(
            label: context.l10n.uiMetricsSheetStages,
            value: _stageSummary(context.l10n, metrics['stages'] as Map),
            detail: context.l10n.metricsStagesHint,
          ),
        _Row(
          label: context.l10n.uiMetricsSheetTokensSec,
          value: tps == null ? '—' : tps.toStringAsFixed(1),
        ),
        _Row(
          label: context.l10n.uiMetricsSheetFirstToken,
          value: firstMs == null ? '—' : '${firstMs.round()} ms',
        ),
        _Row(
          label: context.l10n.uiMetricsSheetTokens,
          value: context.l10n.metricsTokenCounts(
            '${tokens?.toInt() ?? '—'}',
            '${prompt?.toInt() ?? '—'}',
          ),
        ),
        _Row(
          label: context.l10n.uiMetricsSheetContext,
          value: '${used?.toInt() ?? '—'} / ${size?.toInt() ?? '—'}',
          detail: trimmed > 0
              ? context.l10n.metricsTrimmedMessages(trimmed)
              : null,
          tone: fill != null && fill > 0.9 ? c.warning : null,
        ),
        if (fill != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppDesign.md),
            child: ClipRRect(
              borderRadius: AppDesign.radius(AppDesign.rFull),
              child: LinearProgressIndicator(
                value: fill,
                minHeight: 3,
                color: fill > 0.9 ? c.warning : c.accent,
              ),
            ),
          ),
        _Row(
          label: context.l10n.uiMetricsSheetPeakRSS,
          value: rss == null ? '—' : '${rss.round()} MB',
        ),
        Divider(color: c.hairline, height: AppDesign.lg),
        _ModelRow(model: model),
        _Row(
          label: context.l10n.uiMetricsSheetTemplate,
          value: metrics['hasTemplate'] == true
              ? context.l10n.metricsTemplateEmbedded
              : context.l10n.metricsTemplateFamilyFallback,
        ),
        _Row(
          label: context.l10n.uiMetricsSheetThinking,
          value: metrics['supportsThinking'] == true
              ? context.l10n.metricsThinkingNative
              : context.l10n.metricsThinkingPrompted,
        ),
      ],
    );
  }
}

class _ModelRow extends StatelessWidget {
  final ModelInfo? model;
  const _ModelRow({required this.model});

  @override
  Widget build(BuildContext context) => _Row(
    label: context.l10n.uiMetricsSheetModel,
    value: model == null
        ? context.l10n.metricsNoModel
        : '${model!.displayName} · ${model!.sizeLabel} · ${model!.quantLabel}',
  );
}

/// One instrument line: muted label left, mono value right-aligned.
class _Row extends StatelessWidget {
  final String label, value;
  final String? detail;
  final Color? tone;
  const _Row({
    required this.label,
    required this.value,
    this.detail,
    this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppDesign.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: context.text.label.copyWith(color: c.textFaint),
                ),
              ),
              const SizedBox(width: AppDesign.md),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: context.text.monoStrong.copyWith(
                    color: tone ?? c.text,
                  ),
                ),
              ),
            ],
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail!,
                textAlign: TextAlign.right,
                style: context.text.mono.copyWith(color: tone ?? c.textMuted),
              ),
            ),
        ],
      ),
    );
  }
}

/// "plan 1.8 s · search 1.2 s · read 6.4 s · answer 9.7 s"
String _stageSummary(AppLocalizations t, Map stages) {
  final labels = {
    'loadMs': t.metricsStageLoad,
    'judgeMs': t.metricsStageJudge,
    'planMs': t.metricsStagePlan,
    'searchMs': t.metricsStageSearch,
    'readMs': t.metricsStageRead,
    'budgetMs': t.metricsStageFit,
    'generateMs': t.metricsStageAnswer,
  };
  final parts = <String>[];
  for (final e in labels.entries) {
    final ms = (stages[e.key] as num?)?.toInt() ?? 0;
    if (ms >= 100) parts.add('${e.value} ${(ms / 1000).toStringAsFixed(1)} s');
  }
  return parts.isEmpty ? '—' : parts.join(' · ');
}
