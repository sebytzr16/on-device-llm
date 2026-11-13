import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/blur_switcher.dart';
import '../core/motion/pressable.dart';
import '../core/platform/cpu_cores.dart';
import '../core/providers/shared_providers.dart';
import '../data/storage/model_storage.dart';
import '../data/storage/gguf_metadata.dart';
import '../features/adapters/adapter_store.dart';
import '../features/models/domain/entities/model_catalog.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../features/models/presentation/providers/model_recommendations_provider.dart';
import '../features/presets/domain/preset.dart';
import '../features/presets/presentation/providers/presets_provider.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../features/settings/domain/settings_scope.dart';
import '../features/settings/domain/setting_specs.dart';
import '../features/settings/presentation/setting_labels.dart';
import '../features/settings/presentation/providers/effective_settings_provider.dart';
import '../features/settings/presentation/providers/model_profiles_provider.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import '../inference/engine/diffusiongemma_engine.dart';
import '../inference/engine/llama_engine.dart';
import 'inspector_panel.dart';
import 'load_settings/analytical_estimate.dart';
import 'model_speed_section.dart';
import 'model_tune_section.dart';
import 'model_preset_menu.dart';

part 'load_settings/speculation.dart';
part 'load_settings/advanced_fields.dart';
part 'load_settings/estimate.dart';

/// LM Studio-style settings for one model, saved in its model profile: how
/// it loads (GPU offload, context, flash attention, KV cache, threads) and
/// how it answers (temperature and the other sampling settings). The
/// memory estimate uses GGUF metadata immediately; optional native
/// measurements refine it in the background.
Future<void> showDesktopLoadSettings(BuildContext context, ModelInfo model) =>
    showAppDialog<void>(
      context: context,
      builder: (_) => _LoadSettingsDialog(model: model),
    );

/// The keys this dialog owns in a model profile.
const _loadKeys = {
  'nGpuLayers',
  'projectorDevice',
  'vramReserveMb',
  'useMmap',
  'useMlock',
  'mainGpu',
  'splitMode',
  'offloadKv',
  'swaFull',
  'nCpuMoe',
  'moeCacheSizeMb',
  'moeCacheCpuShare',
  'expertsUsed',

  'contextSize',
  'imageMaxTokens',
  'flashAttention',
  'mtp',
  'speculationMode',
  'draftModelId',
  'draftMaxTokens',
  'draftMinP',
  'draftGpuLayers',
  'kvCacheType',
  'vCacheType',
  'cpuThreads',
  'batchSize',
  'microBatchSize',
  'batchThreads',
  'ropeScaling',
  'ropeFreqBase',
  'ropeFreqScale',
  'yarnExtFactor',
  'yarnAttnFactor',
  'yarnBetaFast',
  'yarnBetaSlow',
  'yarnOrigCtx',
  'chatTemplate',
};

const _advancedSamplingKeys = {
  'logitBias',
  'seed',
  'typicalP',
  'topNSigma',
  'xtcProbability',
  'xtcThreshold',
  'repeatLastN',
  'frequencyPenalty',
  'dryMultiplier',
  'dryBase',
  'dryAllowedLength',
  'dryPenaltyLastN',
  'stopSequences',
  'responseFormat',
  'jsonSchema',
  'grammar',
  'samplerOrder',
};
const _advancedMemoryKeys = {
  'promptCache',
  'promptStoreMb',
  'keepTokens',
  'contextOverflow',
};

/// Everything the dialog saves: how the model loads and how it answers.
final _ownKeys = {
  ..._loadKeys,
  ...desktopSamplingKeys,
  ..._advancedSamplingKeys,
  ..._advancedMemoryKeys,
};

class _LoadSettingsDialog extends ConsumerStatefulWidget {
  final ModelInfo model;
  const _LoadSettingsDialog({required this.model});

  @override
  ConsumerState<_LoadSettingsDialog> createState() =>
      _LoadSettingsDialogState();
}

class _LoadSettingsDialogState extends ConsumerState<_LoadSettingsDialog> {
  late Map<String, dynamic> _profile;
  final _template = TextEditingController();
  String _embeddedTemplate = '';
  bool _templateReadError = false;
  bool _overrideTemplate = false;
  Map<String, dynamic>? _estimate;
  String? _estimateError;
  bool _measuring = false;
  GgufMetadata? _metadata;

  /// The draft/DFlash model's header, file size and path, for the estimate.
  (GgufMetadata?, int, String?)? _draft;
  Timer? _debounce;
  int _generation = 0;
  int _fieldVersion = 0;
  // Estimates by the memory-relevant part of the load config: moving a
  // slider back, or changing threads or the template, answers at once.
  final _estimates = <String, Map<String, dynamic>>{};
  String? _measuredKey;
  (ChatLoad, Map<String, dynamic>)? _held;
  // The model's layer count and trained context, from the first estimate.
  int _layers = 0, _trained = 0;
  List<String> _mtpHeads = const [];
  String? _autoHead;
  bool _dflashSupported = false;
  final Map<String, String> _headIssues = {};

  ModelInfo get m => widget.model;

  @override
  void initState() {
    super.initState();
    _profile = Map.of(ref.read(modelProfilesProvider.notifier).of(m.id));
    _overrideTemplate = (_profile['chatTemplate'] as String? ?? '').isNotEmpty;
    _template.text = _profile['chatTemplate'] as String? ?? '';
    _readTemplate();
    _metadata = m.localPath == null ? null : GgufMetadata.cached(m.localPath!);
    _layers = _metadata?.blockCount ?? 0;
    _trained = _metadata?.contextLength ?? 0;
    _estimate = _analytical();
    _readMetadata();
    _measure();
    _listMtpHeads();
    _readSpeculationCapability();
  }

  Future<void> _readTemplate() async {
    if (m.localPath == null) return;
    try {
      final info = await ref
          .read(llamaEngineProvider)
          .adapterInfo(m.localPath!);
      if (!mounted) return;
      setState(() {
        _embeddedTemplate =
            (info['keys'] as Map?)?['tokenizer.chat_template'] as String? ?? '';
        if (!_overrideTemplate) _template.text = _embeddedTemplate;
      });
    } catch (_) {
      if (mounted) setState(() => _templateReadError = true);
    }
  }

  void _resetTemplate() {
    _overrideTemplate = false;
    _template.text = _embeddedTemplate;
    _set('chatTemplate', '');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _template.dispose();
    super.dispose();
  }

  /// The settings a load would use with the draft profile in place.
  InferenceSettings _resolved() => resolveSettings(
    global: ref.read(settingsProvider),
    defaults: ref.read(settingsProvider.notifier).defaults,
    profiles: {...ref.read(modelProfilesProvider), m.id: _profile},
    preset: ref.read(presetsProvider).active,
    chat: ref.read(chatOverridesProvider),
    recommendations: ref.read(modelRecommendationsProvider),
    model: m,
  ).effective;

  /// The model's own answer settings: the profile over the maker's and the
  /// user's, without the chat or a preset on top.
  ResolvedSettings _modelOnly() => resolveSettings(
    global: ref.read(settingsProvider),
    defaults: ref.read(settingsProvider.notifier).defaults,
    profiles: {...ref.read(modelProfilesProvider), m.id: _profile},
    preset: Preset.general,
    chat: const {},
    recommendations: ref.read(modelRecommendationsProvider),
    model: m,
  );

  void _setSampling(InferenceSettings from, InferenceSettings next) {
    final before = from.toJson(), after = next.toJson();
    for (final key in desktopSamplingKeys) {
      if (before[key] != after[key]) _set(key, after[key]);
    }
  }

  void _update(VoidCallback fn) => setState(fn);

  void _set(String key, Object? value) {
    _update(() {
      if (value == null) {
        _profile.remove(key);
        _fieldVersion++;
      } else {
        _profile[key] = value;
      }
    });
    if (key == 'chatTemplate' ||
        desktopSamplingKeys.contains(key) ||
        _advancedSamplingKeys.contains(key) ||
        _advancedMemoryKeys.contains(key)) {
      return;
    }
    _generation++;
    _measuredKey = null;
    _update(() => _estimate = _analytical());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _measure);
  }

  /// Whether this model's engine fixes [key]: shown, dimmed and inert so the
  /// saved value is visible but cannot be changed (audit E23).
  bool _fixedKey(String key) =>
      m.id == diffusionGemmaModelId &&
      (_loadKeys.contains(key) || _advancedMemoryKeys.contains(key)) &&
      !diffusionGemmaHonoursLoad(key);

  Widget _fixed(Widget child, {bool fixed = true}) => fixed
      ? Opacity(opacity: 0.45, child: IgnorePointer(child: child))
      : child;

  Future<void> _save({bool load = false}) async {
    _debounce?.cancel();
    _generation++;
    final keep = Map<String, dynamic>.of(
      ref.read(modelProfilesProvider.notifier).of(m.id),
    )..removeWhere((k, _) => _ownKeys.contains(k));
    for (final k in _ownKeys) {
      if (_profile.containsKey(k)) keep[k] = _profile[k];
    }
    // Every layer is saved as 999, not the model's count: only "all" lets
    // the engine move the vision projector to RAM to keep every layer on
    // the card (Gemma 4 E4B fell from 43 to 31 layers on 8 GB without it).
    if (keep['nGpuLayers'] is int && _layers > 0) {
      final n = keep['nGpuLayers'] as int;
      keep['nGpuLayers'] = n >= _layers ? 999 : n.clamp(0, _layers);
    }
    await ref.read(modelProfilesProvider.notifier).set(m.id, keep);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final manager = ref.read(modelManagerProvider.notifier);
    final loaded = ref.read(modelManagerProvider).loadedModelId == m.id;
    Navigator.pop(context);
    if (!load) return;
    try {
      // A loaded model is reloaded so the new settings take effect.
      if (loaded) await manager.unloadModel();
      await manager.loadModel(m);
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text(_plain(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    // A load or unload meanwhile (Optimize, another window) changes what is
    // free: measure again.
    ref.listen(
      modelManagerProvider.select((s) => (s.loadedModelId, s.isLoadingModel)),
      (_, _) {
        _estimates.clear();
        _measuredKey = null;
        _measure();
      },
    );
    ref.listen(adaptersProvider, (_, _) => _measure());
    final t = context.l10n;
    final c = context.colors;
    final s = _resolved();
    final answer = _modelOnly();
    final layers = _layers > 0 ? _layers : 64;
    final gpuAuto = s.nGpuLayers >= layers;
    // DiffusionGemma's host fixes most of a load profile (audit E23).
    final dg = m.id == diffusionGemmaModelId;
    final maxContext = _trained > 0
        ? _trained.clamp(4096, InferenceSettings.maxContext)
        : 131072;
    final busy =
        ref.watch(sessionBusyProvider) ||
        ref.watch(modelManagerProvider.select((s) => s.isLoadingModel));
    return Dialog(
      insetPadding: const EdgeInsets.all(32),
      shape: RoundedRectangleBorder(
        borderRadius: AppDesign.radius(AppDesign.rLg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 24, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.desktopLoadSettingsTitle,
                          style: context.text.title,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${m.displayName} · ${m.sizeLabel}',
                          overflow: TextOverflow.ellipsis,
                          style: context.text.caption.copyWith(
                            color: c.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: t.cancel,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(28, 12, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ModelOptimizeSection(
                            key: const ValueKey('load-optimize'),
                            model: m,
                            settings: s,
                            onTuned: (profile) {
                              setState(() {
                                for (final key in profile.keys) {
                                  if (profile[key] != null) {
                                    _profile[key] = profile[key];
                                  } else {
                                    _profile.remove(key);
                                  }
                                }
                              });
                              _measure();
                            },
                          ),
                          const SizedBox(height: 18),
                          Text(
                            t.desktopLoadSettingsHint,
                            style: context.text.caption.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                          if (dg) ...[
                            const SizedBox(height: 8),
                            Text(
                              t.dgFixedSettings,
                              style: context.text.caption.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          ],
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.desktopLoadSettingsGpu,
                                  style: context.text.label,
                                ),
                              ),
                              Text(
                                '${t.all} · ${t.desktopLoadSettingsGpuAuto}',
                                style: context.text.small.copyWith(
                                  color: c.textMuted,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: gpuAuto,
                                onChanged: (v) => _set(
                                  'nGpuLayers',
                                  v
                                      ? 999
                                      : ((_estimate?['gpuLayers'] as num?)
                                                    ?.toInt() ??
                                                layers - 1)
                                            .clamp(0, layers - 1),
                                ),
                              ),
                            ],
                          ),
                          Text(t.projectorDevice, style: context.text.label),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            key: const Key('ttft-projector'),
                            showSelectedIcon: false,
                            segments: [
                              ButtonSegment(
                                value: 'auto',
                                label: Text(t.projectorAuto),
                              ),
                              ButtonSegment(
                                value: 'gpu',
                                label: Text(t.projectorGpu),
                              ),
                              ButtonSegment(
                                value: 'cpu',
                                label: Text(t.projectorCpu),
                              ),
                            ],
                            selected: {s.projectorDevice},
                            onSelectionChanged: dg
                                ? null
                                : (v) => _set('projectorDevice', v.first),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.projectorDeviceHelp,
                            style: context.text.caption.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                          if (!gpuAuto)
                            DesktopSlider(
                              label: t.desktopLoadSettingsGpuLayers(
                                s.nGpuLayers.clamp(0, layers),
                                layers,
                              ),
                              value: s.nGpuLayers.clamp(0, layers).toDouble(),
                              min: 0,
                              max: layers.toDouble(),
                              divisions: layers,
                              format: (v) => '${v.round()}',
                              onChanged: (v) => _set(
                                'nGpuLayers',
                                v.round() >= layers ? 999 : v.round(),
                              ),
                            ),
                          const SizedBox(height: 10),
                          DesktopSlider(
                            label: t.desktopLoadSettingsContext,
                            value: _contextStep(
                              s.contextSize,
                              maxContext,
                            ).toDouble(),
                            min: 0,
                            max: _contextSteps(maxContext).length - 1.0,
                            divisions: _contextSteps(maxContext).length - 1,
                            format: (v) =>
                                _tokens(_contextSteps(maxContext)[v.round()]),
                            onChanged: (v) => _set(
                              'contextSize',
                              _contextSteps(maxContext)[v.round()],
                            ),
                          ),
                          if (_trained > 0)
                            Text(
                              t.desktopLoadSettingsTrained(_tokens(_trained)),
                              style: context.text.caption.copyWith(
                                color: c.textFaint,
                              ),
                            ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.desktopLoadSettingsFlash,
                                  style: context.text.label,
                                ),
                              ),
                              Switch(
                                value: s.flashAttention,
                                onChanged: dg
                                    ? null
                                    : (v) => _set('flashAttention', v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            t.desktopLoadSettingsKv,
                            style: context.text.label,
                          ),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            segments: [
                              const ButtonSegment(
                                value: 'fp16',
                                label: Text('F16'),
                              ),
                              const ButtonSegment(
                                value: 'q8_0',
                                label: Text('Q8_0'),
                              ),
                              const ButtonSegment(
                                value: 'q4_0',
                                label: Text('Q4_0'),
                              ),
                              if (_estimate?['supportsFp8Kv'] == true ||
                                  s.kvCacheType == KvCacheType.f8_e4m3)
                                ButtonSegment(
                                  value: 'f8_e4m3',
                                  label: Text(t.kvCacheFp8),
                                ),
                            ],
                            selected: {s.kvCacheType.name},
                            onSelectionChanged: dg
                                ? null
                                : (v) {
                                    _set('kvCacheType', v.first);
                                    _set('vCacheType', null);
                                  },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            t.desktopLoadSettingsKvHint,
                            style: context.text.caption.copyWith(
                              color: c.textFaint,
                            ),
                          ),
                          const SizedBox(height: 14),
                          DesktopSlider(
                            label: t.desktopLoadSettingsThreads,
                            value: s.cpuThreads.toDouble(),
                            min: 0,
                            // Follow the real core count instead of a fixed
                            // 16-thread ceiling.
                            max: CpuCores.desktop.toDouble(),
                            divisions: CpuCores.desktop,
                            format: (v) => v == 0
                                ? t.desktopLoadSettingsAuto
                                : '${v.round()}',
                            onChanged: (v) => _set('cpuThreads', v.round()),
                          ),
                          _fixed(
                            DesktopSlider(
                              label: t.desktopLoadSettingsBatch,
                              value: _batchStep(s.batchSize).toDouble(),
                              min: 0,
                              max: _batches.length - 1.0,
                              divisions: _batches.length - 1,
                              format: (v) => _batches[v.round()] == 0
                                  ? t.desktopLoadSettingsAuto
                                  : '${_batches[v.round()]}',
                              onChanged: (v) =>
                                  _set('batchSize', _batches[v.round()]),
                            ),
                            fixed: dg,
                          ),
                          const SizedBox(height: 18),
                          _fixed(_speculation(s), fixed: dg),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.desktopModelSettingsSampling,
                                  style: context.text.label,
                                ),
                              ),
                              DesktopModelPresetMenu(
                                modelId: m.id,
                                profile: _profile,
                                onActivated: (profile) => setState(() {
                                  _profile.removeWhere(
                                    (k, _) => desktopSamplingKeys.contains(k),
                                  );
                                  _profile.addAll({
                                    for (final e in profile.entries)
                                      if (desktopSamplingKeys.contains(e.key))
                                        e.key: e.value,
                                  });
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            t.desktopModelSettingsSamplingHint,
                            style: context.text.caption.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ModelSpeedSection(
                            key: const ValueKey('load-speed'),
                            model: m,
                            settings: s,
                          ),
                          const SizedBox(height: 16),
                          DesktopSamplingFields(
                            settings: answer.effective,
                            source: (key) =>
                                desktopSettingSource(t, answer.originOf(key)),
                            onChanged: (next) =>
                                _setSampling(answer.effective, next),
                          ),
                          _advancedGroup(t.desktopDeepLoad, 'load', const [
                            'vramReserveMb',
                            'useMmap',
                            'useMlock',
                            'mainGpu',
                            'splitMode',
                            'offloadKv',
                            'swaFull',
                            'nCpuMoe',
                            'moeCacheSizeMb',
                            'moeCacheCpuShare',
                            'expertsUsed',

                            'microBatchSize',
                            'batchThreads',
                            'imageMaxTokens',
                            'vCacheType',
                            'ropeScaling',
                            'ropeFreqBase',
                            'ropeFreqScale',
                            'yarnExtFactor',
                            'yarnAttnFactor',
                            'yarnBetaFast',
                            'yarnBetaSlow',
                            'yarnOrigCtx',
                          ], answer),
                          _advancedGroup(
                            t.desktopDeepSampling,
                            'sampling',
                            _advancedSamplingKeys.toList(),
                            answer,
                          ),
                          _advancedGroup(
                            t.desktopDeepSpeculative,
                            'speculative',
                            const [
                              'draftMaxTokens',
                              'draftMinP',
                              'draftGpuLayers',
                            ],
                            answer,
                          ),
                          _advancedGroup(
                            t.desktopDeepMemory,
                            'memory',
                            _advancedMemoryKeys.toList(),
                            answer,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t.desktopPromptTemplate,
                            style: context.text.label,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            t.desktopPromptTemplateHint,
                            style: context.text.caption.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              t.desktopPromptTemplateOverride,
                              style: context.text.small,
                            ),
                            value: _overrideTemplate,
                            onChanged: dg
                                ? null
                                : (value) {
                                    if (!value) {
                                      _resetTemplate();
                                      return;
                                    }
                                    setState(() => _overrideTemplate = true);
                                    _set('chatTemplate', _template.text);
                                  },
                          ),
                          TextField(
                            key: const Key('desktop-prompt-template'),
                            controller: _template,
                            readOnly: dg || !_overrideTemplate,
                            minLines: 4,
                            maxLines: 10,
                            style: context.text.mono.copyWith(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: t.desktopPromptTemplateMissing,
                              errorText: _templateReadError
                                  ? t.desktopPromptTemplateError
                                  : null,
                              errorMaxLines: 3,
                            ),
                            onChanged: dg
                                ? null
                                : (value) => _set('chatTemplate', value),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: dg ? null : _resetTemplate,
                              child: Text(t.desktopPromptTemplateReset),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(4, 12, 24, 16),
                      child: _EstimatePanel(
                        estimate: _estimate,
                        error: _estimateError,
                        measuring: _measuring,
                        requestedContext: s.contextSize,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 24, 20),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () {
                      setState(
                        () => _profile.removeWhere(
                          (k, _) => _ownKeys.contains(k),
                        ),
                      );
                      _resetTemplate();
                      _measure();
                    },
                    child: Text(t.desktopLoadSettingsReset),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t.cancel),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    child: OutlinedButton(
                      onPressed: _save,
                      child: Text(t.save),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pressable(
                    child: FilledButton(
                      onPressed: busy || m.localPath == null
                          ? null
                          : () => _save(load: true),
                      child: Text(t.desktopLoadSettingsSaveLoad),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 0 = the app's automatic batch size.
const _batches = [0, 64, 128, 256, 512, 1024, 2048];

int _batchStep(int batch) {
  var best = 0;
  for (var i = 0; i < _batches.length; i++) {
    if ((_batches[i] - batch).abs() < (_batches[best] - batch).abs()) best = i;
  }
  return best;
}

/// Powers of two from 2K up to [max], plus [max] itself.
List<int> _contextSteps(int max) => [
  for (var n = 2048; n < max; n *= 2) n,
  max,
];

int _contextStep(int context, int max) {
  final steps = _contextSteps(max);
  var best = 0;
  for (var i = 0; i < steps.length; i++) {
    if ((steps[i] - context).abs() < (steps[best] - context).abs()) best = i;
  }
  return best;
}
