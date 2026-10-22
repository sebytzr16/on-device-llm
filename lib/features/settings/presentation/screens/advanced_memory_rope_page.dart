part of 'advanced_pages_2.dart';

// KV cache, RoPE/YaRN scaling and draft speculation.

/// Load-time memory and position-encoding controls, plus speculative
/// decoding with a draft model (ABI 6).
class MemoryRopePage extends ConsumerWidget {
  const MemoryRopePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final c = context.colors;
    final models = ref.watch(modelManagerProvider);
    final metrics = ref.watch(chatProvider.select((x) => x.metrics));
    final downloaded = models.catalog.where((m) => m.isDownloaded).toList();
    final draftIds = <String>['', for (final m in downloaded) m.id];
    final draftValue = draftIds.contains(s.draftModelId) ? s.draftModelId : '';
    final trained = (metrics['contextTrain'] as num?)?.toInt();
    final proposed = (metrics['draftProposed'] as num?)?.toInt() ?? 0;
    final accepted = (metrics['draftAccepted'] as num?)?.toInt() ?? 0;
    final draftPaused = metrics['draftDisabled'] == true;
    return _Scaffold(
      title: context.l10n.uiAdvancedMemoryRopePageMemoryRoPESpeculation,
      children: [
        SettingsSection(
          label: context.l10n.sectionCachePrecision,
          children: [
            SettingDropdown<KvCacheType>(
              icon: Icons.storage_rounded,
              label: context.l10n.uiAdvancedMemoryRopePageKCache,
              hint: context.l10n.uiAdvancedMemoryRopePagePrecisionOfCachedKeys,
              value: s.kvCacheType,
              items: KvCacheType.values,
              labelOf: kvCacheLabel,
              onChanged: (v) => n.update(s.copyWith(kvCacheType: v)),
            ),
            SettingDropdown<KvCacheType?>(
              label: context.l10n.uiAdvancedMemoryRopePageVCache,
              hint: context
                  .l10n
                  .uiAdvancedMemoryRopePagePrecisionOfCachedValuesQuantisingV,
              value: s.vCacheType,
              items: [null, ...KvCacheType.values],
              labelOf: (v) => v == null ? 'Same as K' : kvCacheLabel(v),
              onChanged: (v) => n.update(
                s.copyWith(vCacheType: v, clearVCacheType: v == null),
              ),
            ),
          ],
        ),
        SettingsSection(
          label: context.l10n.sectionRope,
          children: [
            SettingDropdown<RopeScaling>(
              icon: Icons.open_in_full_rounded,
              label: context.l10n.uiAdvancedMemoryRopePageRoPEScaling,
              hint: context
                  .l10n
                  .uiAdvancedMemoryRopePageHowPositionsBeyondTheTrainedContext,
              value: s.ropeScaling,
              items: RopeScaling.values,
              labelOf: (v) => switch (v) {
                RopeScaling.model => 'Model default',
                RopeScaling.none => 'None',
                RopeScaling.linear => 'Linear',
                RopeScaling.yarn => 'YaRN',
              },
              onChanged: (v) => n.update(s.copyWith(ropeScaling: v)),
            ),
            if (trained != null && trained > 0)
              SettingsNote(
                'The loaded model was trained for ${tokenCount(trained)} tokens.',
                icon: Icons.info_outline,
              ),
            _NumberRow(
              icon: Icons.waves_rounded,
              label: context.l10n.uiAdvancedMemoryRopePageRoPEFrequencyBase,
              value: s.ropeFreqBase,
              off: 0,
              offLabel: 'Model value',
              hint: context.l10n.uiAdvancedMemoryRopePageEG1000000ForModelsThat,
              onChanged: (v) => n.update(s.copyWith(ropeFreqBase: v)),
            ),
            _NumberRow(
              icon: Icons.waves_rounded,
              label: context.l10n.uiAdvancedMemoryRopePageRoPEFrequencyScale,
              value: s.ropeFreqScale,
              off: 0,
              offLabel: 'Model value',
              hint: context.l10n.uiAdvancedMemoryRopePage0Scale1EG0,
              onChanged: (v) => n.update(s.copyWith(ropeFreqScale: v)),
              max: 1,
            ),
            if (s.ropeScaling == RopeScaling.yarn) ...[
              _NumberRow(
                icon: Icons.functions_rounded,
                label: context.l10n.uiAdvancedMemoryRopePageYaRNOriginalContext,
                value: s.yarnOrigCtx.toDouble(),
                off: 0,
                offLabel: 'Model value',
                hint: context
                    .l10n
                    .uiAdvancedMemoryRopePageTheContextTheModelWasTrained,
                integer: true,
                onChanged: (v) => n.update(s.copyWith(yarnOrigCtx: v.round())),
              ),
              _NumberRow(
                icon: Icons.functions_rounded,
                label:
                    context.l10n.uiAdvancedMemoryRopePageYaRNExtrapolationMix,
                value: s.yarnExtFactor,
                off: -1,
                offLabel: 'Model value',
                hint: context
                    .l10n
                    .uiAdvancedMemoryRopePage0InterpolationOnly1FullExtrapolation,
                max: 1,
                onChanged: (v) => n.update(s.copyWith(yarnExtFactor: v)),
              ),
              _NumberRow(
                icon: Icons.functions_rounded,
                label: context.l10n.uiAdvancedMemoryRopePageYaRNAttentionFactor,
                value: s.yarnAttnFactor,
                off: 1,
                offLabel: '1.0 (default)',
                hint: context
                    .l10n
                    .uiAdvancedMemoryRopePageMagnitudeScalingUsually10,
                max: 8,
                onChanged: (v) => n.update(s.copyWith(yarnAttnFactor: v)),
              ),
              _NumberRow(
                icon: Icons.functions_rounded,
                label: context.l10n.uiAdvancedMemoryRopePageYaRNBetaFast,
                value: s.yarnBetaFast,
                off: 32,
                offLabel: '32 (default)',
                hint:
                    context.l10n.uiAdvancedMemoryRopePageLowCorrectionDimension,
                max: 128,
                onChanged: (v) => n.update(s.copyWith(yarnBetaFast: v)),
              ),
              _NumberRow(
                icon: Icons.functions_rounded,
                label: context.l10n.uiAdvancedMemoryRopePageYaRNBetaSlow,
                value: s.yarnBetaSlow,
                off: 1,
                offLabel: '1 (default)',
                hint: context
                    .l10n
                    .uiAdvancedMemoryRopePageHighCorrectionDimension,
                max: 128,
                onChanged: (v) => n.update(s.copyWith(yarnBetaSlow: v)),
              ),
            ],
          ],
        ),
        SettingsSection(
          label: context.l10n.sectionSpeculative,
          children: [
            SettingDropdown<String>(
              icon: Icons.fast_forward_rounded,
              label: context.l10n.uiAdvancedMemoryRopePageDraftModel,
              hint:
                  context.l10n.uiAdvancedMemoryRopePageASmallerModelWithTheSame,
              value: draftValue,
              items: draftIds,
              labelOf: (id) => id.isEmpty
                  ? 'Off'
                  : downloaded.where((m) => m.id == id).first.displayName,
              onChanged: (v) => n.update(s.copyWith(draftModelId: v)),
            ),
            if (s.draftModelId.isNotEmpty)
              SettingSlider(
                label: context.l10n.uiAdvancedMemoryRopePageDraftTokensPerRound,
                hint: context
                    .l10n
                    .uiAdvancedMemoryRopePageHowManyTokensTheDraftProposes,
                value: s.draftMaxTokens.toDouble(),
                min: 1,
                max: InferenceSettings.maxDraftTokens.toDouble(),
                divisions: InferenceSettings.maxDraftTokens - 1,
                display: '${s.draftMaxTokens}',
                onChanged: (v) =>
                    n.update(s.copyWith(draftMaxTokens: v.round())),
              ),
            if (proposed > 0)
              SettingsNote(
                'Last answer: $accepted of $proposed drafted tokens accepted '
                '(${(100 * accepted / proposed).round()}%) with ${metrics['draftModel']}. '
                '${draftPaused ? 'Drafting was paused for the rest of that answer after ${metrics['draftRounds']} rounds (${(metrics['draftAcceptRate'] as num? ?? 1) < 0.35 ? 'acceptance under 35%' : 'slower than plain decoding'}); it retries every answer. ' : ''}'
                'Below ~60% the draft usually costs more than it saves.',
                icon: Icons.speed_outlined,
                tone: accepted / proposed >= .6 && !draftPaused
                    ? c.success
                    : c.warning,
              ),
          ],
        ),
        SettingsNote(
          'These apply on the next model load.',
          tone: c.warning,
          icon: Icons.schedule_outlined,
        ),
      ],
    );
  }
}
