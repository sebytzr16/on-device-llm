part of '../load_settings_dialog.dart';

// The advanced load, sampling, speculation and memory fields.

extension _AdvancedFieldsSection on _LoadSettingsDialogState {
  Widget _advancedField(String key, ResolvedSettings resolved) {
    final t = context.l10n;
    final spec = SettingSpec.byKey(key)!;
    final value = resolved.effective.toJson()[key];
    final source = desktopSettingSource(t, resolved.originOf(key));
    final label = _deepLabel(t, key);
    Widget editor;
    if (spec.kind == SettingKind.boolean) {
      editor = Switch(
        key: Key('desktopDeep-$key'),
        value: value == true,
        onChanged: (v) => _set(key, v),
      );
    } else if (spec.kind == SettingKind.choice) {
      editor = DropdownButton<String>(
        key: Key('desktopDeep-$key'),
        value: value?.toString() ?? spec.options.first,
        items: [
          for (final option in spec.options)
            if (option != 'f8_e4m3' ||
                _estimate?['supportsFp8Kv'] == true ||
                value == option)
              DropdownMenuItem(
                value: option,
                child: Text(
                  nativeSettingOption(t, key, option) ??
                      (option.isEmpty ? t.desktopDeepSameAsK : option),
                ),
              ),
        ],
        onChanged: (v) => _set(key, v),
      );
    } else {
      final raw = value is Map
          ? jsonEncode(value)
          : value is List
          ? value.join('\n')
          : '$value';
      editor = SizedBox(
        key: Key('desktopDeep-$key'),
        width:
            spec.kind == SettingKind.text || spec.kind == SettingKind.stringList
            ? null
            : 118,
        child: TextFormField(
          key: ValueKey('$key-$_fieldVersion'),
          initialValue: raw,
          maxLines:
              spec.kind == SettingKind.text ||
                  spec.kind == SettingKind.stringList
              ? 3
              : 1,
          keyboardType:
              spec.kind == SettingKind.integer ||
                  spec.kind == SettingKind.number
              ? const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                )
              : TextInputType.multiline,
          onChanged: (raw) {
            Object? next;
            if (spec.kind == SettingKind.integer) {
              next = int.tryParse(raw);
            } else if (spec.kind == SettingKind.number) {
              next = double.tryParse(raw);
            } else if (spec.kind == SettingKind.stringList) {
              next = raw
                  .split('\n')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
            } else {
              next = raw;
            }
            if (next != null) {
              final valid = spec.coerce(next);
              if (valid != null) _set(key, valid);
            }
          },
        ),
      );
    }
    final field = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.text.label)),
              if (spec.kind != SettingKind.text &&
                  spec.kind != SettingKind.stringList)
                editor,
              IconButton(
                key: Key('desktopDeep-reset-$key'),
                tooltip: t.desktopDeepReset,
                onPressed: _profile.containsKey(key)
                    ? () => _set(key, null)
                    : null,
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
              ),
            ],
          ),
          if (spec.kind == SettingKind.text ||
              spec.kind == SettingKind.stringList)
            editor,
          Text(
            '${_deepHint(t, key)} · $source',
            style: context.text.caption.copyWith(
              color: context.colors.textMuted,
            ),
          ),
        ],
      ),
    );
    return _fixed(field, fixed: _fixedKey(key));
  }

  Widget _advancedGroup(
    String title,
    String id,
    List<String> keys,
    ResolvedSettings resolved,
  ) => ExpansionTile(
    key: Key('desktopDeep-group-$id'),
    title: Text(title, style: context.text.label),
    childrenPadding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
    children: [for (final key in keys) _advancedField(key, resolved)],
  );
}

String _deepLabel(AppLocalizations t, String key) => switch (key) {
  'useMmap' => t.nativeSetUseMmap,
  'useMlock' => t.nativeSetUseMlock,
  'draftMinP' => t.nativeSetDraftMinP,
  'promptStoreMb' => t.nativeSetPromptStoreMb,
  'mainGpu' => t.nativeSetMainGpu,
  'splitMode' => t.nativeSetSplitMode,
  'offloadKv' => t.nativeSetOffloadKv,
  'swaFull' => t.nativeSetSwaFull,
  'nCpuMoe' => t.nativeSetNCpuMoe,
  'moeCacheSizeMb' => t.nativeSetMoeCacheSizeMb,
  'moeCacheCpuShare' => t.nativeSetMoeCacheCpuShare,
  'expertsUsed' => t.nativeSetExpertsUsed,
  'draftGpuLayers' => t.nativeSetDraftGpuLayers,
  'keepTokens' => t.nativeSetKeepTokens,
  'contextOverflow' => t.nativeSetContextOverflow,
  'logitBias' => t.nativeSetLogitBias,
  'vramReserveMb' => t.desktopDeepVramReserveMb,
  'microBatchSize' => t.desktopDeepMicroBatchSize,
  'imageMaxTokens' => t.desktopDeepImageMaxTokens,
  'batchThreads' => t.desktopDeepBatchThreads,
  'vCacheType' => t.desktopDeepVCacheType,
  'ropeScaling' => t.desktopDeepRopeScaling,
  'ropeFreqBase' => t.desktopDeepRopeFreqBase,
  'ropeFreqScale' => t.desktopDeepRopeFreqScale,
  'yarnExtFactor' => t.desktopDeepYarnExtFactor,
  'yarnAttnFactor' => t.desktopDeepYarnAttnFactor,
  'yarnBetaFast' => t.desktopDeepYarnBetaFast,
  'yarnBetaSlow' => t.desktopDeepYarnBetaSlow,
  'yarnOrigCtx' => t.desktopDeepYarnOrigCtx,
  'seed' => t.desktopDeepSeed,
  'typicalP' => t.desktopDeepTypicalP,
  'topNSigma' => t.desktopDeepTopNSigma,
  'xtcProbability' => t.desktopDeepXtcProbability,
  'xtcThreshold' => t.desktopDeepXtcThreshold,
  'repeatLastN' => t.desktopDeepRepeatLastN,
  'frequencyPenalty' => t.desktopDeepFrequencyPenalty,
  'dryMultiplier' => t.desktopDeepDryMultiplier,
  'dryBase' => t.desktopDeepDryBase,
  'dryAllowedLength' => t.desktopDeepDryAllowedLength,
  'dryPenaltyLastN' => t.desktopDeepDryPenaltyLastN,
  'stopSequences' => t.desktopDeepStopSequences,
  'responseFormat' => t.desktopDeepResponseFormat,
  'jsonSchema' => t.desktopDeepJsonSchema,
  'grammar' => t.desktopDeepGrammar,
  'samplerOrder' => t.desktopDeepSamplerOrder,
  'draftMaxTokens' => t.desktopDeepDraftMaxTokens,
  'promptCache' => t.desktopDeepPromptCache,
  _ => key,
};

String _deepHint(AppLocalizations t, String key) =>
    key == 'draftMaxTokens' || key == 'draftMinP' || key == 'draftGpuLayers'
    ? t.desktopDeepSpeculativeHint
    : _loadKeys.contains(key)
    ? t.desktopDeepLoadHint
    : _advancedMemoryKeys.contains(key)
    ? t.desktopDeepMemoryHint
    : t.desktopDeepSamplingHint;
