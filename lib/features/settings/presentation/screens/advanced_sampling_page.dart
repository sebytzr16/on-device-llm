part of 'advanced_pages_2.dart';

// Sampling extras: seed, stop sequences, penalties, the sampler order.

/// Advanced sampling (ABI 6): seed, stop sequences, OpenAI-style penalties,
/// typical/XTC/top-n-sigma/DRY samplers and the chain order.
class SamplingExtrasPage extends ConsumerWidget {
  const SamplingExtrasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final c = context.colors;
    return _Scaffold(
      title: context.l10n.uiAdvancedSamplingPageMoreSampling,
      children: [
        SettingsSection(
          label: context.l10n.sectionReproducibility,
          children: [
            SettingsRow(
              leading: const Icon(Icons.casino_outlined),
              key: const Key('seed-row'),
              title: Text(context.l10n.uiAdvancedSamplingPageSeed),
              subtitle: Text(
                s.seed == 0
                    ? 'Random every answer'
                    : '${s.seed} · the same prompt and settings reproduce the answer',
              ),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () async {
                final v = await askInteger(
                  context,
                  title: context.l10n.uiAdvancedSamplingPageSeed0Random,
                  current: s.seed,
                  min: 0,
                  max: 0x7fffffff,
                );
                if (v != null) await n.update(s.copyWith(seed: v));
              },
            ),
            SettingsRow(
              leading: const Icon(Icons.block_rounded),
              key: const Key('stop-sequences-row'),
              title: Text(context.l10n.uiAdvancedSamplingPageStopSequences),
              subtitle: Text(
                s.stopSequences.isEmpty
                    ? 'None · the answer ends at the model\'s end token'
                    : s.stopSequences.map((x) => '"$x"').join(', '),
              ),
              trailing: const Icon(Icons.edit_outlined, size: 20),
              onTap: () => _editStops(context, s, n),
            ),
          ],
        ),
        SettingsSection(
          label: context.l10n.sectionPenalties,
          children: [
            SettingSlider(
              label: context.l10n.uiAdvancedSamplingPagePresencePenalty,
              hint: context.l10n.uiAdvancedSamplingPageOnceATokenHasAppearedIt,
              value: s.presencePenalty,
              min: -2,
              max: 2,
              divisions: 40,
              display: s.presencePenalty.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(presencePenalty: v)),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedSamplingPageFrequencyPenalty,
              hint: context
                  .l10n
                  .uiAdvancedSamplingPageEachRepetitionAddsToThePenalty,
              value: s.frequencyPenalty,
              min: -2,
              max: 2,
              divisions: 40,
              display: s.frequencyPenalty.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(frequencyPenalty: v)),
            ),
            SettingChoice<int>(
              label: context.l10n.uiAdvancedSamplingPagePenaltyWindow,
              hint: context
                  .l10n
                  .uiAdvancedSamplingPageHowManyRecentTokensTheRepetition,
              value: s.repeatLastN,
              options: const [0, 64, 128, 256, 512, 1024, 2048],
              labelOf: (v) => v == 0 ? 'Off' : '$v',
              onChanged: (v) => n.update(s.copyWith(repeatLastN: v)),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedSamplingPageDRYMultiplier,
              hint: context
                  .l10n
                  .uiAdvancedSamplingPageDRYPenalisesRepeatingWholeSequencesRather,
              value: s.dryMultiplier,
              min: 0,
              max: 2,
              divisions: 40,
              display: s.dryMultiplier == 0
                  ? 'Off'
                  : s.dryMultiplier.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(dryMultiplier: v)),
            ),
            if (s.dryMultiplier > 0) ...[
              SettingSlider(
                label: context.l10n.uiAdvancedSamplingPageDRYBase,
                hint: context
                    .l10n
                    .uiAdvancedSamplingPageGrowthOfThePenaltyWithThe,
                value: s.dryBase,
                min: 1,
                max: 4,
                divisions: 30,
                display: s.dryBase.toStringAsFixed(2),
                onChanged: (v) => n.update(s.copyWith(dryBase: v)),
              ),
              SettingSlider(
                label: context.l10n.uiAdvancedSamplingPageDRYAllowedLength,
                hint: context
                    .l10n
                    .uiAdvancedSamplingPageRepeatsShorterThanThisAreFree,
                value: s.dryAllowedLength.toDouble(),
                min: 1,
                max: 16,
                divisions: 15,
                display: '${s.dryAllowedLength}',
                onChanged: (v) =>
                    n.update(s.copyWith(dryAllowedLength: v.round())),
              ),
            ],
          ],
        ),
        SettingsSection(
          label: context.l10n.sectionExtraSamplers,
          children: [
            SettingSlider(
              label: context.l10n.uiAdvancedSamplingPageTypicalP,
              hint: context
                  .l10n
                  .uiAdvancedSamplingPageKeepsTokensWhoseSurpriseIsClose,
              value: s.typicalP,
              min: 0,
              max: 1,
              divisions: 100,
              display: s.typicalP >= 1 ? 'Off' : s.typicalP.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(typicalP: v)),
            ),
            SettingSlider(
              label: context.l10n.uiAdvancedSamplingPageXTCProbability,
              hint: context
                  .l10n
                  .uiAdvancedSamplingPageWithThisProbabilityTheMostLikely,
              value: s.xtcProbability,
              min: 0,
              max: 1,
              divisions: 20,
              display: s.xtcProbability == 0
                  ? 'Off'
                  : s.xtcProbability.toStringAsFixed(2),
              onChanged: (v) => n.update(s.copyWith(xtcProbability: v)),
            ),
            if (s.xtcProbability > 0)
              SettingSlider(
                label: context.l10n.uiAdvancedSamplingPageXTCThreshold,
                hint: context
                    .l10n
                    .uiAdvancedSamplingPageTokensAboveThisProbabilityAreCandidates,
                value: s.xtcThreshold,
                min: 0,
                max: .5,
                divisions: 50,
                display: s.xtcThreshold.toStringAsFixed(2),
                onChanged: (v) => n.update(s.copyWith(xtcThreshold: v)),
              ),
            SettingSlider(
              label: context.l10n.uiAdvancedSamplingPageTopNSigma,
              hint: context
                  .l10n
                  .uiAdvancedSamplingPageKeepsTokensWithinNStandardDeviations,
              value: s.topNSigma < 0 ? 0 : s.topNSigma,
              min: 0,
              max: 5,
              divisions: 50,
              display: s.topNSigma <= 0
                  ? 'Off'
                  : s.topNSigma.toStringAsFixed(1),
              onChanged: (v) =>
                  n.update(s.copyWith(topNSigma: v <= 0 ? -1 : v)),
            ),
          ],
        ),
        SettingsSection(
          label: context.l10n.sectionSamplerOrder,
          children: [
            const SettingsNote(
              'Samplers run top to bottom. Long-press and drag to reorder; llama.cpp\'s default is penalties, dry, top-n-sigma, top-k, typical-p, top-p, min-p, xtc, temperature.',
            ),
            ReorderableListView(
              key: const Key('sampler-order'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: true,
              onReorderItem: (from, to) {
                final order = [...s.samplerOrder];
                order.insert(to, order.removeAt(from));
                n.update(s.copyWith(samplerOrder: order));
              },
              children: [
                for (final name in s.samplerOrder)
                  SettingsRow(
                    key: ValueKey('sampler-$name'),
                    dense: true,
                    leading: Icon(Icons.drag_handle, color: c.textFaint),
                    title: Text(samplerLabel(name)),
                  ),
              ],
            ),
            TextButton(
              onPressed: () => n.update(
                s.copyWith(samplerOrder: InferenceSettings.samplerNames),
              ),
              child: Text(context.l10n.uiAdvancedSamplingPageResetOrder),
            ),
          ],
        ),
        const SettingsNote(
          'Sampling changes take effect on the next response.',
        ),
      ],
    );
  }

  Future<void> _editStops(
    BuildContext context,
    InferenceSettings s,
    SettingsNotifier n,
  ) async {
    final controller = TextEditingController(text: s.stopSequences.join('\n'));
    final result = await showAppDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(context.l10n.uiAdvancedSamplingPageStopSequences),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: context.l10n.uiAdvancedSamplingPageOnePerLineUpTo8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.uiAdvancedSamplingPageCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, [
              for (final l in controller.text.split('\n'))
                if (l.isNotEmpty && l.trim().isNotEmpty) l,
            ]),
            child: Text(context.l10n.uiAdvancedSamplingPageSave),
          ),
        ],
      ),
    );
    if (result != null) await n.update(s.copyWith(stopSequences: result));
  }
}

String samplerLabel(String name) => switch (name) {
  'penalties' => 'Repetition / presence / frequency penalties',
  'dry' => 'DRY',
  'top_n_sigma' => 'Top-n-sigma',
  'top_k' => 'Top-K',
  'typ_p' => 'Typical-P',
  'top_p' => 'Top-P',
  'min_p' => 'Min-P',
  'xtc' => 'XTC',
  'temperature' => 'Temperature',
  _ => name,
};
