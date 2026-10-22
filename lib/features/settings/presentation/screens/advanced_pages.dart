import '../../../../core/l10n/l10n.dart';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design/app_design.dart';
import '../../../../data/network/web_search/duckduckgo_scraper.dart';
import '../../../../data/storage/download_manager.dart';
import '../../../models/domain/entities/model_catalog.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../../chat/presentation/providers/chat_provider.dart';
import '../../../chat/presentation/providers/search_misses.dart';
import '../../../zim/zim_tile.dart';
import '../../domain/entities/inference_settings.dart';
import '../../domain/setting_specs.dart';
import '../../domain/settings_scope.dart';
import '../providers/effective_settings_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_labels.dart';
import '../widgets/settings_widgets.dart';
import '../../../../core/island/status_island.dart';
import '../../../../core/design/app_dialog.dart';

/// Layer 3 (North Star 6.6): each advanced group is its own pushed page so
/// the main settings screen stays short.
class _AdvancedScaffold extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _AdvancedScaffold({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: const [SavedIndicator()]),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDesign.lg,
          AppDesign.sm,
          AppDesign.lg,
          AppDesign.xxl,
        ),
        children: children,
      ),
    ),
  );
}

class ContextBatchPage extends ConsumerWidget {
  const ContextBatchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final c = context.colors;
    // What the loaded model was trained for, once one has been loaded.
    final trained =
        ref.watch(chatProvider.select((x) => x.metrics['contextTrain']))
            as num?;
    final beyond = trained != null && trained > 0 && s.contextSize > trained;
    return _AdvancedScaffold(
      title: context.l10n.uiAdvancedPagesContextBatch,
      children: [
        SettingsGroup(
          children: [
            SettingChoice<int>(
              label: context.l10n.uiAdvancedPagesContextSize,
              hint: context.l10n.uiAdvancedPagesTokensTheModelCanSeeAt,
              value: s.contextSize,
              options: contextPresets,
              labelOf: tokenCount,
              onChanged: (v) => n.update(s.copyWith(contextSize: v)),
              onCustom: () async {
                final v = await askInteger(
                  context,
                  title: context.l10n.uiAdvancedPagesContextSizeTokens,
                  current: s.contextSize,
                  min: InferenceSettings.minContext,
                  max: InferenceSettings.maxContext,
                );
                if (v != null) await n.update(s.copyWith(contextSize: v));
              },
            ),
            SettingChoice<int>(
              label: context.l10n.imageTokenBudget,
              hint: context.l10n.imageTokenBudgetHint,
              value: s.imageMaxTokens,
              options: const [256, 512, 1024, 2048, 4096],
              labelOf: tokenCount,
              onChanged: (v) => n.update(s.copyWith(imageMaxTokens: v)),
              onCustom: () async {
                final v = await askInteger(
                  context,
                  title: context.l10n.imageTokenBudget,
                  current: s.imageMaxTokens,
                  min: 64,
                  max: 16384,
                );
                if (v != null) await n.update(s.copyWith(imageMaxTokens: v));
              },
            ),
            if (trained != null && trained > 0)
              SettingsNote(
                // The bridge caps the context to the trained length unless
                // linear or YaRN scaling stretches it.
                !beyond
                    ? context.l10n.contextTrainedFor(
                        tokenCount(trained.toInt()),
                      )
                    : s.ropeScaling == RopeScaling.linear ||
                          s.ropeScaling == RopeScaling.yarn
                    ? context.l10n.contextTrainedForStretched(
                        tokenCount(trained.toInt()),
                      )
                    : context.l10n.contextTrainedForCapped(
                        tokenCount(trained.toInt()),
                      ),
                tone: beyond ? c.warning : null,
                icon: beyond
                    ? Icons.warning_amber_outlined
                    : Icons.info_outline,
              ),
            SettingChoice<int>(
              label: context.l10n.uiAdvancedPagesBatchSize,
              hint:
                  context.l10n.uiAdvancedPagesPromptTokensSubmittedPerStepAuto,
              value: s.batchSize,
              options: batchPresets,
              labelOf: (v) => v == 0 ? 'Auto' : '$v',
              onChanged: (v) => n.update(s.copyWith(batchSize: v)),
            ),
            SettingChoice<int>(
              label: context.l10n.uiAdvancedPagesMicroBatch,
              hint: context.l10n.uiAdvancedPagesTokensPerComputeStepWithinA,
              value: s.microBatchSize,
              options: batchPresets,
              labelOf: (v) => v == 0 ? 'Auto' : '$v',
              onChanged: (v) => n.update(s.copyWith(microBatchSize: v)),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.history_rounded),
              key: const Key('prompt-cache'),
              title: Text(
                context.l10n.uiAdvancedPagesKeepConversationInContext,
              ),
              subtitle: Text(
                context.l10n.uiAdvancedPagesOnlyNewTextIsEvaluatedOn,
              ),
              value: s.promptCache,
              onChanged: (v) => n.update(s.copyWith(promptCache: v)),
            ),
          ],
        ),
        SettingsNote(
          'Context and batch changes apply the next time a model loads.',
          tone: c.warning,
          icon: Icons.schedule_outlined,
        ),
      ],
    );
  }
}

class HardwarePage extends ConsumerWidget {
  const HardwarePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return _AdvancedScaffold(
      title: context.l10n.uiAdvancedPagesHardware,
      children: [
        SettingsGroup(
          children: [
            SettingDropdown<GpuBackend>(
              icon: Icons.developer_board_outlined,
              label: context.l10n.uiAdvancedPagesBackend,
              hint: context.l10n.uiAdvancedPagesAutomaticUsesCPUOpenCL2Faster,
              value: s.backend,
              items: availableBackends(),
              labelOf: backendLabel,
              onChanged: (v) => n.update(s.copyWith(backend: v)),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesGPULayers,
              hint: context.l10n.uiAdvancedPagesLayersOffloadedToTheGPUIgnored,
              value: s.nGpuLayers.toDouble(),
              min: 0,
              max: 999,
              divisions: 999,
              display: gpuLayersLabel(s.nGpuLayers),
              onChanged: (v) => n.update(s.copyWith(nGpuLayers: v.round())),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesCPUThreadsDecode,
              hint: context
                  .l10n
                  .uiAdvancedPagesWorkerThreadsWhileTheAnswerStreams,
              value: s.cpuThreads.toDouble(),
              min: 0,
              max: 16,
              divisions: 16,
              display: threadsLabel(s),
              onChanged: (v) => n.update(s.copyWith(cpuThreads: v.round())),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesCPUThreadsPrefill,
              hint: context.l10n.uiAdvancedPagesThreadsWhileThePromptIsRead,
              value: s.batchThreads.toDouble(),
              min: 0,
              max: 16,
              divisions: 16,
              display: batchThreadsLabel(s),
              onChanged: (v) => n.update(s.copyWith(batchThreads: v.round())),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.bolt_rounded),
              title: Text(context.l10n.uiAdvancedPagesFlashAttention),
              subtitle: Text(
                context
                    .l10n
                    .uiAdvancedPagesFasterAttentionKernelWithLowerMemory,
              ),
              value: s.flashAttention,
              onChanged: (v) => n.update(s.copyWith(flashAttention: v)),
            ),
            SettingDropdown<KvCacheType>(
              icon: Icons.storage_rounded,
              label: context.l10n.uiAdvancedPagesKVCache,
              hint: context.l10n.uiAdvancedPagesPrecisionOfCachedAttentionState,
              value: s.kvCacheType,
              items: KvCacheType.values,
              labelOf: kvCacheLabel,
              onChanged: (v) => n.update(s.copyWith(kvCacheType: v)),
            ),
          ],
        ),
        SettingsNote(
          'Hardware changes apply on the next model load.',
          tone: context.colors.warning,
          icon: Icons.schedule_outlined,
        ),
      ],
    );
  }
}

class SamplingPage extends ConsumerWidget {
  const SamplingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    // Request 2026-10-04: a key the user never set shows what the
    // loaded model's makers recommend, which is what the sampler uses.
    final r = ref.watch(effectiveSettingsProvider);
    final layer = r.layers
        .where((l) => l.id == SettingsLayer.idRecommended)
        .firstOrNull;
    final rec = layer?.values ?? const <String, dynamic>{};
    final saved = s.toJson(), device = n.defaults.toJson();
    bool own(String k) => '${saved[k]}' != '${device[k]}';
    final v = InferenceSettings.fromJson({
      ...saved,
      for (final e in rec.entries)
        if (!own(e.key)) e.key: e.value,
    });
    final mine = [
      for (final k in rec.keys)
        if (own(k)) k,
    ];
    return _AdvancedScaffold(
      title: context.l10n.uiAdvancedPagesSampling,
      children: [
        if (rec.isNotEmpty)
          SettingsNote(
            mine.isEmpty
                ? '${layer!.label}: ${rec.entries.map((e) => '${SettingSpec.byKey(e.key)?.label ?? e.key} ${SettingSpec.byKey(e.key)?.display(e.value) ?? e.value}').join(', ')}. Moving a slider sets your own value for every model.'
                : 'Your values for ${mine.map((k) => SettingSpec.byKey(k)?.label ?? k).join(', ')} replace what this model recommends.',
            icon: Icons.auto_awesome_outlined,
          ),
        if (mine.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('use-recommended-sampling'),
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text("Use the model's recommended values"),
              onPressed: () => n.update(
                InferenceSettings.fromJson({
                  ...saved,
                  for (final k in mine) k: device[k],
                }).copyWith(remoteApiKeys: s.remoteApiKeys),
              ),
            ),
          ),
        SettingsGroup(
          children: [
            SettingSlider(
              label: context.l10n.uiAdvancedPagesTemperature,
              hint: context
                  .l10n
                  .uiAdvancedPagesRandomnessLowerIsMoreFocusedHigher,
              value: v.temperature,
              min: 0,
              max: 2,
              divisions: 40,
              display: v.temperature.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(temperature: v)),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesTopP,
              hint: context.l10n.uiAdvancedPagesSampleFromTheSmallestSetOf,
              value: v.topP,
              min: 0,
              max: 1,
              divisions: 100,
              display: v.topP.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(topP: v)),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesMinP,
              hint: context.l10n.uiAdvancedPagesDropTokensLessLikelyThanThis,
              value: v.minP,
              min: 0,
              max: 1,
              divisions: 100,
              display: v.minP.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(minP: v)),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesTopK,
              hint: context.l10n.uiAdvancedPagesOnlyTheKMostLikelyTokens,
              value: v.topK.toDouble(),
              min: 0,
              max: 200,
              divisions: 200,
              display: '${v.topK}',
              onChanged: (v) => n.update(s.copyWith(topK: v.round())),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesRepetitionPenalty,
              hint: context
                  .l10n
                  .uiAdvancedPagesDiscouragesRepeatingRecentTokens100,
              value: v.repetitionPenalty,
              min: 1.0,
              max: 2.0,
              divisions: 20,
              display: v.repetitionPenalty.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(repetitionPenalty: v)),
            ),
            SettingChoice<int>(
              label: context.l10n.uiAdvancedPagesMaxTokens,
              hint:
                  context.l10n.uiAdvancedPagesUpperBoundOnOneResponseReasoning,
              value: s.maxTokens,
              options: responsePresets,
              labelOf: tokenCount,
              onChanged: (v) => n.update(s.copyWith(maxTokens: v)),
              onCustom: () async {
                final v = await askInteger(
                  context,
                  title: context.l10n.uiAdvancedPagesMaxTokensPerResponse,
                  current: s.maxTokens,
                  min: InferenceSettings.minResponseTokens,
                  max: InferenceSettings.maxResponseTokens,
                );
                if (v != null) await n.update(s.copyWith(maxTokens: v));
              },
            ),
          ],
        ),
        const SettingsNote(
          'Sampling changes take effect on the next response.',
        ),
      ],
    );
  }
}

class ReasoningSearchPage extends ConsumerWidget {
  const ReasoningSearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return _AdvancedScaffold(
      title: context.l10n.uiAdvancedPagesReasoningSearch,
      children: [
        SettingsSection(
          label: context.l10n.sectionReasoning,
          children: [
            SettingsSwitchRow(
              secondary: const Icon(Icons.psychology_outlined),
              title: Text(context.l10n.uiAdvancedPagesThinkingMode),
              subtitle: Text(
                context
                    .l10n
                    .uiAdvancedPagesShowModelGeneratedReasoningWhenSupported,
              ),
              value: s.thinkingModeEnabled,
              onChanged: (v) => n.update(s.copyWith(thinkingModeEnabled: v)),
            ),
            SettingChoice<int>(
              label: context.l10n.uiAdvancedPagesThinkingBudget,
              hint: context
                  .l10n
                  .uiAdvancedPagesReasoningTokensAllowedBeforeTheBlock,
              value: s.thinkingBudgetTokens,
              options: thinkingBudgetPresets,
              labelOf: (v) =>
                  v == 0 ? context.l10n.thinkingBudgetUnlimited : tokenCount(v),
              onChanged: (v) => n.update(s.copyWith(thinkingBudgetTokens: v)),
              onCustom: () async {
                final v = await askInteger(
                  context,
                  title: context
                      .l10n
                      .uiAdvancedPagesThinkingBudgetTokens0Unlimited,
                  current: s.thinkingBudgetTokens,
                  min: 0,
                  max: InferenceSettings.maxThinkingBudget,
                );
                if (v != null) {
                  await n.update(s.copyWith(thinkingBudgetTokens: v));
                }
              },
            ),
          ],
        ),
        SettingsSection(
          label: context.l10n.settingsSearchSection,
          children: [
            SettingDropdown<String>(
              icon: Icons.language_rounded,
              key: const Key('search-region'),
              label: context.l10n.uiAdvancedPagesSearchAndNewsRegion,
              hint: context.l10n.searchRegionHint(
                _regionName(
                  DuckDuckGoScraper.regionFor(
                    s.localeCode,
                    localeName: Platform.localeName,
                  ),
                ),
              ),
              value: s.searchRegion,
              items: ['', ...InferenceSettings.searchRegions],
              labelOf: (v) => v.isEmpty
                  ? context.l10n.searchRegionAutomatic
                  : _regionName(v),
              onChanged: (v) => n.update(s.copyWith(searchRegion: v)),
            ),
            SettingsRow(
              key: const Key('search-misses'),
              // The questions themselves, not only a copy button.
              onTap: ref.watch(searchMissesProvider).isEmpty
                  ? null
                  : () => showAppDialog<void>(
                      context: context,
                      builder: (dialog) => AlertDialog(
                        title: Text(dialog.l10n.searchMissesTitle),
                        content: Container(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                          ),
                          width: double.maxFinite,
                          child: ListView(
                            shrinkWrap: true,
                            children: [
                              for (final q in ref.read(searchMissesProvider))
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: AppDesign.sm,
                                  ),
                                  child: SelectableText('• $q'),
                                ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialog),
                            child: Text(dialog.l10n.uiBenchmarkDialogDone),
                          ),
                        ],
                      ),
                    ),
              leading: const Icon(Icons.travel_explore),
              title: Text(context.l10n.searchMissesTitle),
              subtitle: Text(
                context.l10n.searchMissesHint(
                  ref.watch(searchMissesProvider).length,
                ),
              ),
              trailing: ref.watch(searchMissesProvider).isEmpty
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: context.l10n.copyResponse,
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: ref.read(searchMissesProvider).join('\n'),
                              ),
                            );
                            if (context.mounted) {
                              showIslandToast(
                                context,
                                context.l10n.commonCopied,
                                tone: IslandTone.done,
                              );
                            }
                          },
                        ),
                        IconButton(
                          tooltip: context.l10n.delete,
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () =>
                              ref.read(searchMissesProvider.notifier).clear(),
                        ),
                      ],
                    ),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesSearchResults,
              hint: context
                  .l10n
                  .uiAdvancedPagesCandidatesTakenFromDuckDuckGoPerQuery,
              value: s.maxSearchResults.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              display: '${s.maxSearchResults}',
              onChanged: (v) =>
                  n.update(s.copyWith(maxSearchResults: v.round())),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesPagesToRead,
              hint: context.l10n.uiAdvancedPagesResultPagesFetchedAndRankedFor,
              value: s.maxPagesRead.toDouble(),
              min: 1,
              max: InferenceSettings.maxPagesReadLimit.toDouble(),
              divisions: InferenceSettings.maxPagesReadLimit - 1,
              display: '${s.maxPagesRead}',
              onChanged: (v) => n.update(s.copyWith(maxPagesRead: v.round())),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedPagesResearchTimeBudget,
              hint: context.l10n.uiAdvancedPagesWallClockLimitForReadingAll,
              value: s.researchTimeBudgetSeconds.toDouble(),
              min: InferenceSettings.minResearchSeconds.toDouble(),
              max: InferenceSettings.maxResearchSeconds.toDouble(),
              divisions:
                  (InferenceSettings.maxResearchSeconds -
                      InferenceSettings.minResearchSeconds) ~/
                  5,
              display: '${s.researchTimeBudgetSeconds} s',
              onChanged: (v) =>
                  n.update(s.copyWith(researchTimeBudgetSeconds: v.round())),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.travel_explore_rounded),
              key: const Key('research-loop'),
              title: Text(
                context.l10n.uiAdvancedPagesModelDrivenResearchExperimental,
              ),
              subtitle: Text(
                s.toolsEnabled && s.toolWeb
                    ? context.l10n.researchLoopHint
                    : context.l10n.researchLoopNeedsTools,
              ),
              value: s.researchLoop,
              onChanged: s.toolsEnabled && s.toolWeb
                  ? (v) => n.update(s.copyWith(researchLoop: v))
                  : null,
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.manage_search_rounded),
              title: Text(
                context.l10n.uiAdvancedPagesModelWritesTheSearchQueries,
              ),
              subtitle: Text(
                context.l10n.uiAdvancedPagesTheLocalModelTurnsYourQuestion,
              ),
              value: s.searchQueryPlanning,
              onChanged: (v) => n.update(s.copyWith(searchQueryPlanning: v)),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.youtube_searched_for_rounded),
              key: const Key('search-again'),
              title: Text(context.l10n.searchAgainSetting),
              subtitle: Text(context.l10n.searchAgainHint),
              value: s.searchAgain,
              onChanged: (v) => n.update(s.copyWith(searchAgain: v)),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.menu_book_outlined),
              key: const Key('wikipedia-lookup'),
              title: Text(context.l10n.wikipediaLookupSetting),
              subtitle: Text(context.l10n.wikipediaLookupHint),
              value: s.wikipediaLookup,
              onChanged: (v) => n.update(s.copyWith(wikipediaLookup: v)),
            ),
            const ZimTile(),
          ],
        ),
        SettingsSection(
          label: context.l10n.sectionEvidence,
          children: [
            SettingSlider(
              label: context.l10n.uiAdvancedPagesPassagesGivenToTheModel,
              hint: context
                  .l10n
                  .uiAdvancedPagesBestMatchingPassagesAbout250Tokens,
              value: s.evidencePassages.toDouble(),
              min: InferenceSettings.minEvidencePassages.toDouble(),
              max: InferenceSettings.maxEvidencePassages.toDouble(),
              divisions:
                  InferenceSettings.maxEvidencePassages -
                  InferenceSettings.minEvidencePassages,
              display: '${s.evidencePassages}',
              onChanged: (v) =>
                  n.update(s.copyWith(evidencePassages: v.round())),
            ),
            SettingsSwitchRow(
              secondary: const Icon(Icons.fact_check_outlined),
              key: const Key('figure-check'),
              title: Text(context.l10n.uiAdvancedPagesFlagUnsupportedFigures),
              subtitle: Text(
                context.l10n.uiAdvancedPagesAfterAGroundedAnswerNumbersVersions,
              ),
              value: s.figureCheck,
              onChanged: (v) => n.update(s.copyWith(figureCheck: v)),
            ),
            if (s.figureCheck) const _SupportCheckTile(),
          ],
        ),
        SettingsNote(context.l10n.webModeNote),
      ],
    );
  }
}

String _regionName(String region) => switch (region) {
  'ca-en' => 'Canada (English)',
  'ca-fr' => 'Canada (français)',
  'us-en' => 'United States',
  'uk-en' => 'United Kingdom',
  'au-en' => 'Australia',
  'nz-en' => 'New Zealand',
  'ie-en' => 'Ireland',
  'in-en' => 'India',
  'za-en' => 'South Africa',
  'fr-fr' => 'France',
  'be-fr' => 'Belgique',
  'ch-fr' => 'Suisse (français)',
  'de-de' => 'Deutschland',
  'it-it' => 'Italia',
  'es-es' => 'España',
  'mx-es' => 'México',
  'br-pt' => 'Brasil',
  'jp-jp' => 'Japan',
  'wt-wt' => 'No region',
  _ => region,
};

/// The optional source-check model: offer it, show its download, or report
/// it ready with a way to remove it. Being on disk is the opt-in.
class _SupportCheckTile extends ConsumerWidget {
  const _SupportCheckTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final models = ref.watch(modelManagerProvider);
    final manager = ref.read(modelManagerProvider.notifier);
    const key = ModelManagerState.supportCheckKey;
    final progress = models.downloads[key];
    final status = progress?.status;
    final Widget action;
    if (status == DownloadStatus.downloading ||
        status == DownloadStatus.queued) {
      action = OutlinedButton.icon(
        key: const Key('support-check-pause'),
        onPressed: () => manager.pauseDownload(key),
        icon: const Icon(Icons.pause, size: 18),
        label: Text('${(progress!.fraction * 100).round()}%'),
      );
    } else if (status == DownloadStatus.verifying) {
      action = OutlinedButton(
        onPressed: null,
        child: Text(context.l10n.uiKnowledgePageVerifying),
      );
    } else if (models.supportCheckReady) {
      action = OutlinedButton.icon(
        key: const Key('support-check-remove'),
        onPressed: manager.deleteSupportCheck,
        style: OutlinedButton.styleFrom(foregroundColor: c.success),
        icon: const Icon(Icons.check, size: 18),
        label: Text(context.l10n.ready),
      );
    } else {
      action = FilledButton.tonalIcon(
        key: const Key('support-check-add'),
        onPressed: manager.downloadSupportCheck,
        icon: Icon(
          status == DownloadStatus.paused || status == DownloadStatus.failed
              ? Icons.refresh
              : Icons.download_outlined,
          size: 18,
        ),
        label: Text(
          context.l10n.downloadMb(
            (supportCheckModel.sizeBytes / (1024 * 1024)).round(),
          ),
        ),
      );
    }
    return SettingsRow(
      leading: const Icon(Icons.verified_outlined),
      key: const Key('support-check'),
      title: Text(context.l10n.supportCheckTitle),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.supportCheckHint),
          const SizedBox(height: AppDesign.xs),
          action,
        ],
      ),
    );
  }
}
