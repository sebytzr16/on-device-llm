import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/blur_switcher.dart';
import '../core/motion/pressable.dart';
import '../core/providers/shared_providers.dart';
import '../data/storage/model_storage.dart';
import '../data/storage/gguf_metadata.dart';
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
import '../inference/engine/llama_engine.dart';
import 'inspector_panel.dart';
import 'model_speed_section.dart';
import 'model_tune_section.dart';
import 'model_preset_menu.dart';

/// LM Studio-style settings for one model, saved in its model profile: how
/// it loads (GPU offload, context, flash attention, KV cache, threads) and
/// how it answers (temperature and the other sampling settings). The
/// bridge measures what each choice would take (od_estimate) while the
/// user moves the sliders.
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
  'expertsUsed',

  'contextSize',
  'imageMaxTokens',
  'flashAttention',
  'mtp',
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
  Timer? _debounce;
  int _generation = 0;
  int _fieldVersion = 0;
  // Estimates by the memory-relevant part of the load config: moving a
  // slider back, or changing threads or the template, answers at once.
  final _estimates = <String, Map<String, dynamic>>{};
  String? _measuredKey;
  // The model's layer count and trained context, from the first estimate.
  int _layers = 0, _trained = 0;
  List<String> _mtpHeads = const [];
  String? _autoHead;
  final Map<String, String> _headIssues = {};

  ModelInfo get m => widget.model;

  @override
  void initState() {
    super.initState();
    _profile = Map.of(ref.read(modelProfilesProvider.notifier).of(m.id));
    _overrideTemplate = (_profile['chatTemplate'] as String? ?? '').isNotEmpty;
    _template.text = _profile['chatTemplate'] as String? ?? '';
    _readTemplate();
    _measure();
    _listMtpHeads();
  }

  Future<void> _listMtpHeads() async {
    // A head only fits its own base size; others are refused at load.
    final size = gemma4Size(m.fileName);
    final heads = <String>[];
    GgufMetadata? target;
    if (m.localPath != null && await File(m.localPath!).exists()) {
      try {
        target = await GgufMetadata.inspect(m.localPath!);
      } catch (_) {
        /* Report invalid target at load. */
      }
    }
    final selected = _resolved().draftModelId;
    final candidates = {
      ...await mtpHeadFiles(),
      if (selected.startsWith(mtpHeadPrefix) &&
          selected != '$mtpHeadPrefix$mtpOff')
        selected.substring(mtpHeadPrefix.length),
    };
    for (final h in candidates) {
      if (size != null &&
          gemma4Size(p.basename(h)) != null &&
          gemma4Size(p.basename(h)) != size) {
        continue;
      }
      try {
        final metadata = await GgufMetadata.inspect(h);
        final issue = target == null
            ? 'Download the target model first.'
            : metadata.mtpHeadIssueFor(target);
        if (issue == null) {
          heads.add(h);
        } else {
          _headIssues[h] = issue;
        }
      } catch (e) {
        _headIssues[h] = 'Cannot read MTP head: $e';
      }
    }
    final auto = m.localPath == null ? null : autoMtpHead(m.localPath!);
    if (mounted) {
      setState(() {
        _mtpHeads = heads;
        _autoHead = auto;
      });
    }
  }

  /// Copies a picked MTP head (LM Studio's `mtp-*.gguf` sidecar, say) into
  /// the models folder, so it outlives the app it came from.
  Future<void> _addMtpHead() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['gguf'],
    );
    final source = picked.singleOrNull?.path;
    if (source == null) return;
    try {
      final metadata = await GgufMetadata.inspect(source);
      final target = m.localPath == null
          ? null
          : await GgufMetadata.inspect(m.localPath!);
      final issue = target == null
          ? 'Download the target model first.'
          : metadata.mtpHeadIssueFor(target);
      if (issue != null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(issue)));
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cannot read MTP head: $e')));
      }
      return;
    }
    var name = p.basename(source);
    if (!isMtpHeadFile(name)) name = 'mtp-$name';
    final dir = await ModelStorage.modelsDir();
    final target = await importMtpHead(source, dir.path, name);
    if (!mounted) return;
    await _listMtpHeads();
    _set('draftModelId', '$mtpHeadPrefix$target');
  }

  /// The MTP head picker: Auto (the matching head on disk, found beside
  /// the model or in LM Studio's folder), Off, or a chosen head file, and
  /// how many tokens a chosen head drafts per step.
  Widget _mtpHead(InferenceSettings s) {
    final t = context.l10n, c = context.colors;
    final current = s.draftModelId.startsWith(mtpHeadPrefix)
        ? s.draftModelId.substring(mtpHeadPrefix.length)
        : '';
    final heads = {
      ..._mtpHeads,
      if (current.isNotEmpty && current != mtpOff) current,
    }.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(t.desktopMtpHeadLabel, style: context.text.label),
            const SizedBox(width: 12),
            // A dropdown sizes to its widest item; a long head file name
            // squeezed the label to one letter per line.
            Expanded(
              child: DropdownButton<String>(
                key: const Key('desktop-mtp-head'),
                value: current,
                isExpanded: true,
                borderRadius: AppDesign.radius(AppDesign.rMd),
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(
                    value: '',
                    child: Text(
                      _autoHead == null
                          ? t.desktopMtpHeadAutoNone
                          : t.desktopMtpHeadAuto(p.basename(_autoHead!)),
                    ),
                  ),
                  DropdownMenuItem(
                    value: mtpOff,
                    child: Text(t.desktopMtpHeadOff),
                  ),
                  for (final h in heads)
                    DropdownMenuItem(
                      value: h,
                      child: Text(
                        p.basename(h),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  DropdownMenuItem(
                    value: '+',
                    child: Text(t.desktopMtpHeadAdd),
                  ),
                ],
                onChanged: (v) {
                  if (v == '+') {
                    _addMtpHead();
                  } else if (v != null) {
                    _set('draftModelId', v.isEmpty ? null : '$mtpHeadPrefix$v');
                  }
                },
              ),
            ),
          ],
        ),
        Text(
          t.desktopMtpHeadHint,
          style: context.text.caption.copyWith(color: c.textMuted),
        ),
        if (_headIssues[current] != null)
          Text(
            _headIssues[current]!,
            style: context.text.caption.copyWith(color: c.textMuted),
          ),
        if (current.isNotEmpty && current != mtpOff)
          DesktopSlider(
            label: t.desktopMtpHeadTokens,
            value: s.draftMaxTokens.clamp(1, 8).toDouble(),
            min: 1,
            max: 8,
            divisions: 7,
            format: (v) => '${v.round()}',
            onChanged: (v) => _set('draftMaxTokens', v.round()),
          ),
      ],
    );
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

  void _set(String key, Object? value) {
    setState(() {
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
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _measure);
  }

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
    return Padding(
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

  /// The load config without the fields that don't change memory use.
  static String _memoryKey(String config) {
    final map = Map<String, dynamic>.from(jsonDecode(config) as Map);
    for (final k in const [
      'effectiveThreads',
      'effectiveBatchThreads',
      'chatTemplate',
      'draftMaxTokens',
      'draftMinP',
    ]) {
      map.remove(k);
    }
    return jsonEncode(map);
  }

  Future<void> _measure() async {
    final path = m.localPath;
    if (path == null) return;
    final models = ref.read(modelManagerProvider);
    final projector = (m.projector ?? visionProjectors[m.id]);
    final mmproj = projector != null && models.vision.contains(m.id)
        ? (await ModelStorage.modelFile(projector.fileName)).path
        : null;
    if (!mounted) return;
    final settings = _resolved();
    final draft = ref
        .read(modelManagerProvider.notifier)
        .draftPathFor(m, settings.draftModelId);
    final key = _memoryKey(
      LlamaEngine.loadConfig(
        settings: settings,
        mmprojPath: mmproj,
        draftModelPath: draft,
      ),
    );
    if (key == _measuredKey) return;
    final generation = ++_generation;
    final cached = _estimates[key];
    if (cached != null) {
      _measuredKey = key;
      setState(() {
        _estimate = cached;
        _estimateError = null;
        _measuring = false;
      });
      return;
    }
    setState(() => _measuring = true);
    try {
      final result = await _creditLoaded(
        key,
        await ref
            .read(llamaEstimatorProvider)
            .estimate(
              modelPath: path,
              settings: settings,
              mmprojPath: mmproj,
              draftModelPath: draft,
            ),
      );
      _estimates[key] = result;
      if (!mounted || generation != _generation) return;
      _measuredKey = key;
      setState(() {
        _estimate = result;
        _estimateError = null;
        _layers = (result['layers'] as num?)?.toInt() ?? _layers;
        _trained = (result['contextTrain'] as num?)?.toInt() ?? _trained;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _estimate = null;
        _estimateError = _plain(e);
      });
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _measuring = false);
      }
    }
  }

  (ChatLoad, Map<String, dynamic>)? _held;

  /// Planning reads free memory with the chat model still holding its share.
  Future<Map<String, dynamic>> _creditLoaded(
    String key,
    Map<String, dynamic> e,
  ) async {
    final load = ref.read(modelManagerProvider.notifier).loadedConfig;
    if (load == null) return e;
    final metrics = ref.read(llamaEngineProvider).metrics;
    final actual = Map<String, dynamic>.from(
      (metrics['effectiveSettings'] as Map?) ?? const {},
    );
    final same =
        load.modelPath == m.localPath &&
        key ==
            _memoryKey(
              LlamaEngine.loadConfig(
                settings: load.settings,
                mmprojPath: load.mmprojPath,
                draftModelPath: load.draftModelPath,
              ),
            );
    try {
      final held = actual['memoryNeedMb'] != null
          ? {...actual, 'ramNeedMb': actual['memoryNeedMb']}
          : _held?.$1 == load
          ? _held!.$2
          : await ref
                .read(llamaEstimatorProvider)
                .estimate(
                  modelPath: load.modelPath,
                  settings: load.settings,
                  mmprojPath: load.mmprojPath,
                  draftModelPath: load.draftModelPath,
                );
      _held = (load, held);
      final result = <String, dynamic>{...e, 'modelLoaded': true};
      // Prefer the selected card's capacity, even if the fit chose no layers.
      final backend = (metrics['backend'] as String? ?? '').split(' / ').first;
      final card = (e['devices'] as List?)
          ?.cast<Map>()
          .where((d) => d['type'] == 'gpu' && d['backend'] == backend)
          .firstOrNull;
      final total = card?['totalMb'] ?? actual['vramTotalMb'];
      if (total is num && total > 0) result['vramTotalMb'] = total;
      if (result['vramFreeMb'] == null && card?['freeMb'] is num) {
        result['vramFreeMb'] = card!['freeMb'];
      }
      num credit(num free, String need, num? total) {
        final sum = free + ((held[need] as num?) ?? 0);
        return total == null || sum < total ? sum : total;
      }

      final vram = result['vramFreeMb'] as num?;
      final ram = result['ramAvailableMb'] as num?;
      if (vram != null) {
        result['vramFreeMb'] = credit(
          vram,
          'vramNeedMb',
          result['vramTotalMb'] as num?,
        );
      }
      if (ram != null) {
        result['ramAvailableMb'] = credit(
          ram,
          'ramNeedMb',
          result['ramTotalMb'] as num?,
        );
      }
      if (same &&
          actual['contextSize'] != null &&
          actual['gpuLayers'] != null) {
        for (final field in const [
          'contextSize',
          'contextCap',
          'contextTrain',
          'layers',
          'gpuLayers',
          'gpuFit',
          'gpuExpertsOnCpu',
          'vramNeedMb',
        ]) {
          result.remove(field);
          if (actual.containsKey(field)) result[field] = actual[field];
        }
        result['backend'] = metrics['backend'];
        result['ramNeedMb'] = held['ramNeedMb'];
        result['loadedAdmission'] = true;
      }
      return result;
    } catch (_) {
      return {...e, 'modelLoaded': true};
    }
  }

  static String _plain(Object e) {
    final text = '$e';
    final colon = text.indexOf(': ');
    return text.startsWith('Bad state') || text.startsWith('InferenceException')
        ? text.substring(colon + 2)
        : text;
  }

  Future<void> _save({bool load = false}) async {
    _debounce?.cancel();
    _generation++;
    final keep = Map<String, dynamic>.of(
      ref.read(modelProfilesProvider.notifier).of(m.id),
    )..removeWhere((k, _) => _ownKeys.contains(k));
    for (final k in _ownKeys) {
      if (_profile.containsKey(k)) keep[k] = _profile[k];
    }
    if (keep['nGpuLayers'] is int && _layers > 0) {
      keep['nGpuLayers'] = (keep['nGpuLayers'] as int).clamp(0, _layers);
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
    final t = context.l10n;
    final c = context.colors;
    final s = _resolved();
    final answer = _modelOnly();
    final layers = _layers > 0 ? _layers : 64;
    final gpuAuto = s.nGpuLayers >= layers;
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
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(28, 12, 20, 16),
                      children: [
                        ModelOptimizeSection(
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
                                    ? layers
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
                          onSelectionChanged: (v) =>
                              _set('projectorDevice', v.first),
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
                            onChanged: (v) => _set('nGpuLayers', v.round()),
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
                              onChanged: (v) => _set('flashAttention', v),
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
                          segments: const [
                            ButtonSegment(value: 'fp16', label: Text('F16')),
                            ButtonSegment(value: 'q8_0', label: Text('Q8_0')),
                            ButtonSegment(value: 'q4_0', label: Text('Q4_0')),
                          ],
                          selected: {s.kvCacheType.name},
                          onSelectionChanged: (v) {
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
                          max: 16,
                          divisions: 16,
                          format: (v) => v == 0
                              ? t.desktopLoadSettingsAuto
                              : '${v.round()}',
                          onChanged: (v) => _set('cpuThreads', v.round()),
                        ),
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
                        const SizedBox(height: 18),
                        SwitchListTile(
                          key: const Key('desktop-mtp'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            t.desktopMtpLabel,
                            style: context.text.body,
                          ),
                          subtitle: Text(
                            t.desktopMtpHint,
                            style: context.text.caption.copyWith(
                              color: c.textMuted,
                            ),
                          ),
                          value: s.mtp,
                          onChanged: (v) => _set('mtp', v),
                        ),
                        const SizedBox(height: 8),
                        _mtpHead(s),
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
                        ModelSpeedSection(model: m, settings: s),
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
                          onChanged: (value) {
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
                          readOnly: !_overrideTemplate,
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
                          onChanged: (value) => _set('chatTemplate', value),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _resetTemplate,
                            child: Text(t.desktopPromptTemplateReset),
                          ),
                        ),
                      ],
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

String _tokens(int n) => n >= 1024 && n % 1024 == 0 ? '${n ~/ 1024}K' : '$n';

String _gb(num mb) => (mb / 1024).toStringAsFixed(1);

/// What the bridge measured: VRAM and RAM bars, how many layers are on
/// the card, and any context cut.
class _EstimatePanel extends StatelessWidget {
  final Map<String, dynamic>? estimate;
  final String? error;
  final bool measuring;
  final int requestedContext;
  const _EstimatePanel({
    required this.estimate,
    required this.error,
    required this.measuring,
    required this.requestedContext,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final e = estimate;
    final notes = <(IconData, String, Color)>[];
    if (e != null) {
      final gpu = (e['gpuLayers'] as num?)?.toInt() ?? 0;
      final layers = (e['layers'] as num?)?.toInt() ?? 0;
      final onCard = e['vramTotalMb'] != null;
      final needMb = (e['vramNeedMb'] as num?) ?? 0;
      final freeMb = e['vramFreeMb'] as num?;
      // A full card reads 0 MB free, which still spills.
      final spills = onCard && gpu > 0 && freeMb != null && needMb > freeMb;
      final uncertain =
          e['modelLoaded'] == true && e['loadedAdmission'] != true;
      final creditedFits =
          ((e['ramNeedMb'] as num?) ?? 0) <=
              ((e['ramAvailableMb'] as num?) ?? 0) &&
          needMb <= (freeMb ?? 0);
      if (uncertain && creditedFits && gpu == 0) {
        // The occupied card may have forced this plan onto the CPU.
      } else if (!onCard || gpu == 0) {
        notes.add((
          Icons.memory_rounded,
          t.desktopLoadSettingsGpuNone,
          c.textMuted,
        ));
      } else if (spills) {
        // Every layer is on the card but the card is too small: the spill
        // warning below says it, so no "fits" note contradicts it.
      } else if (gpu >= layers) {
        notes.add((
          Icons.check_circle_outline_rounded,
          t.desktopLoadSettingsFitsGpu,
          c.accent,
        ));
      } else {
        notes.add((
          Icons.speed_rounded,
          t.desktopLoadSettingsPartial,
          c.warning,
        ));
      }
      if (spills) {
        // Manual fit (owner, 2026-10-28): warn, never change the count.
        // Windows spills the overflow into shared memory over PCIe.
        notes.add((
          Icons.warning_amber_rounded,
          t.desktopLoadSettingsSpill(
            ((needMb - freeMb) / 1024).toStringAsFixed(1),
          ),
          c.danger,
        ));
      }
      if (onCard && gpu > 0) {
        notes.add((
          Icons.layers_outlined,
          t.desktopLoadSettingsGpuLayers(gpu, layers),
          c.textMuted,
        ));
      }
      if (uncertain) {
        notes.add((
          Icons.info_outline_rounded,
          t.desktopLoadSettingsLoadedNote,
          c.textMuted,
        ));
      }
      if (e['gpuExpertsOnCpu'] == true) {
        notes.add((
          Icons.hub_outlined,
          t.desktopLoadSettingsExperts,
          c.textMuted,
        ));
      }
      final context0 = (e['contextSize'] as num?)?.toInt() ?? requestedContext;
      if (context0 < requestedContext && !(uncertain && creditedFits)) {
        notes.add((
          Icons.content_cut_rounded,
          t.desktopLoadSettingsCapped(_tokens(context0)),
          c.warning,
        ));
      }
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: AppDesign.radius(AppDesign.rMd),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.desktopLoadSettingsEstimate,
                  style: context.text.label,
                ),
              ),
              if (measuring)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          BlurSwitcher(
            child: Column(
              key: ValueKey((e == null, error)),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (e == null && error != null)
                  Text(
                    t.desktopLoadSettingsNoEstimate(error!),
                    style: context.text.small.copyWith(color: c.danger),
                  )
                else if (e == null)
                  Text(
                    t.desktopLoadSettingsMeasuring,
                    style: context.text.small.copyWith(color: c.textMuted),
                  )
                else ...[
                  if (e['vramTotalMb'] != null)
                    _Meter(
                      label: t.desktopLoadSettingsVram,
                      detail:
                          (e['devices'] as List?)
                              ?.cast<Map>()
                              .where((d) => d['type'] == 'gpu')
                              .map((d) => '${d['description']}')
                              .firstOrNull ??
                          '',
                      need: (e['vramNeedMb'] as num?) ?? 0,
                      free: (e['vramFreeMb'] as num?) ?? 0,
                    ),
                  _Meter(
                    label: t.desktopLoadSettingsRam,
                    detail: '',
                    need: (e['ramNeedMb'] as num?) ?? 0,
                    free: (e['ramAvailableMb'] as num?) ?? 0,
                  ),
                  const SizedBox(height: 4),
                  for (final (icon, text, color) in notes)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, size: 15, color: color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              text,
                              style: context.text.small.copyWith(color: color),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final String label, detail;
  final num need, free;
  const _Meter({
    required this.label,
    required this.detail,
    required this.need,
    required this.free,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = free <= 0 ? 1.0 : (need / free).clamp(0.0, 1.0).toDouble();
    final over = free > 0 && need > free;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: context.text.small)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  context.l10n.desktopLoadSettingsUsage(_gb(need), _gb(free)),
                  textAlign: TextAlign.end,
                  style: context.text.mono.copyWith(
                    fontSize: 12,
                    color: over ? c.danger : c.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(end: share),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              borderRadius: AppDesign.radius(3),
              color: over ? c.danger : c.accent,
              backgroundColor: c.text.fade(0.08),
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              overflow: TextOverflow.ellipsis,
              style: context.text.caption.copyWith(color: c.textFaint),
            ),
          ],
        ],
      ),
    );
  }
}

/// Preserve a different file with the same basename, including equal-size files.
Future<String> importMtpHead(
  String source,
  String directory,
  String name,
) async {
  final input = File(source);
  final sourceSize = await input.length();
  String? digest;
  var target = p.join(directory, name);
  var suffix = 1;
  while (await File(target).exists()) {
    if (await File(target).length() == sourceSize) {
      digest ??= (await sha256.bind(input.openRead()).first).toString();
      final existing = (await sha256.bind(File(target).openRead()).first)
          .toString();
      if (digest == existing) return target;
    }
    target = p.join(
      directory,
      '${p.basenameWithoutExtension(name)}-${suffix++}${p.extension(name)}',
    );
  }
  await input.copy(target);
  return target;
}
