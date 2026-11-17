part of '../load_settings_dialog.dart';

// Memory estimation: the bridge's measurement, its cache key, and the panel.

/// The load config without the fields that don't change memory use.
/// Draft length stays in the key: the bridge sizes its rollback slots
/// (`n_rs_seq`) and output limits from it.
String _memoryKey(String config) {
  final map = Map<String, dynamic>.from(jsonDecode(config) as Map);
  for (final k in const [
    'effectiveThreads',
    'effectiveBatchThreads',
    'chatTemplate',
    'draftMinP',
  ]) {
    map.remove(k);
  }
  return jsonEncode(map);
}

extension _EstimateSection on _LoadSettingsDialogState {
  Map<String, dynamic> _analytical() => analyticalMemoryEstimate(
    metadata: _metadata,
    weightsBytes: m.sizeBytes,
    settings: _resolved(),
    hardware:
        _estimate ??
        // Only a probe already made: reading would start a native estimate.
        (ref.exists(detectedHardwareProvider)
            ? ref.read(detectedHardwareProvider).value
            : null) ??
        ref.read(llamaEngineProvider).metrics,
    draft: _draft?.$1,
    draftBytes: _draft?.$2 ?? 0,
  );

  /// The KV cache at the length the plan settled on.
  num _kvMb() {
    final e = _estimate;
    if (e == null) return 0;
    if (e['kvCacheMb'] is num) return e['kvCacheMb'] as num;
    final settings = _resolved();
    final ctx = (e['contextSize'] as num?)?.toInt() ?? settings.contextSize;
    return kvCacheBytes(_metadata, settings.copyWith(contextSize: ctx)) /
        (1024 * 1024);
  }

  Future<void> _readMetadata() async {
    if (m.localPath == null) return;
    try {
      final metadata = await GgufMetadata.inspect(m.localPath!);
      if (!mounted) return;
      _update(() {
        _metadata = metadata;
        _layers = metadata.blockCount ?? _layers;
        _trained = metadata.contextLength ?? _trained;
        if (_measuredKey == null && !_stale) _estimate = _analytical();
      });
    } catch (_) {
      // Catalog weights remain available for missing or non-GGUF files.
    }
  }

  /// The draft's header and size for the instant estimate; off the measure
  /// path so a slow disk never delays the bridge's measurement.
  Future<void> _readDraft(String path) async {
    try {
      final metadata = await GgufMetadata.inspect(path);
      final bytes = await File(path).length();
      if (!mounted || _draft?.$3 != path) return;
      _update(() {
        _draft = (metadata, bytes, path);
        if (_measuredKey == null && !_stale) _estimate = _analytical();
      });
    } catch (_) {
      // A missing or unreadable draft leaves the target-only estimate.
    }
  }

  /// No measurement will come: show the instant estimate instead of a
  /// plan for other settings.
  void _dropStale() {
    if (!_stale || !mounted) return;
    _update(() {
      _stale = false;
      _estimate = _analytical();
    });
  }

  Future<void> _measure() async {
    final path = m.localPath;
    if (path == null || ref.read(sessionBusyProvider)) {
      _dropStale();
      return;
    }
    final generation = ++_generation;
    final settings = _resolved();
    final models = ref.read(modelManagerProvider);
    final projector = (m.projector ?? visionProjectors[m.id]);
    final mmproj = projector != null && models.vision.contains(m.id)
        ? (await ModelStorage.modelFile(projector.fileName)).path
        : null;
    if (!mounted || generation != _generation) return;
    final adapters = await ref.read(adaptersProvider.notifier).resolved(m.id);
    if (!mounted || generation != _generation) return;
    final draft = settings.speculationMode == 'off'
        ? null
        : await ref
              .read(modelManagerProvider.notifier)
              .draftPathFor(m, settings.draftModelId);
    if (!mounted || generation != _generation) return;
    if (draft != _draft?.$3) {
      _draft = (null, 0, draft);
      if (draft != null) unawaited(_readDraft(draft));
    }
    final key = _memoryKey(
      LlamaEngine.loadConfig(
        settings: settings,
        mmprojPath: mmproj,
        adapters: adapters,
        draftModelPath: draft,
      ),
    );
    if (key == _measuredKey) return;
    final cached = _estimates[key];
    if (cached != null) {
      _measuredKey = key;
      _update(() {
        _estimate = cached;
        _estimateError = null;
        _measuring = false;
        _stale = false;
      });
      return;
    }
    // Refinement never gates controls or hides the analytical answer.
    if (ref.read(sessionBusyProvider)) {
      _dropStale();
      return;
    }
    try {
      final result = await _creditLoaded(
        key,
        await ref
            .read(llamaEstimatorProvider)
            .estimate(
              modelPath: path,
              settings: settings,
              mmprojPath: mmproj,
              adapters: adapters,
              draftModelPath: draft,
            ),
      );
      if (!mounted || generation != _generation) return;
      _estimates[key] = result;
      _measuredKey = key;
      _update(() {
        _estimate = result;
        _stale = false;
        _estimateError = null;
        _layers = (result['layers'] as num?)?.toInt() ?? _layers;
        _trained = (result['contextTrain'] as num?)?.toInt() ?? _trained;
      });
    } catch (e, stack) {
      Logger('load_settings').warning('Memory measurement failed', e, stack);
      if (!mounted || generation != _generation) return;
      // Keep the analytical answer when there is one; otherwise say why
      // there is no estimate instead of "Measuring…" forever.
      _update(() {
        if (_stale) {
          _stale = false;
          _estimate = _analytical();
        }
        _estimateError = _estimate == null ? _plain(e) : null;
      });
    } finally {
      if (mounted && generation == _generation) {
        _update(() => _measuring = false);
      }
    }
  }

  /// Planning reads free memory with the chat model still holding its share.
  Future<Map<String, dynamic>> _creditLoaded(
    String key,
    Map<String, dynamic> e,
  ) async {
    if (!mounted) return e;
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
                adapters: load.adapters,
                draftModelPath: load.draftModelPath,
              ),
            );
    try {
      final held = actual['memoryNeedMb'] != null
          ? {
              ...actual,
              'ramNeedMb':
                  ((actual['memoryNeedMb'] as num?) ?? 0) -
                  ((actual['memoryPagedMb'] as num?) ?? 0),
            }
          : _held?.$1 == load
          ? _held!.$2
          : ref.read(sessionBusyProvider)
          ? const <String, dynamic>{}
          : await ref
                .read(llamaEstimatorProvider)
                .estimate(
                  modelPath: load.modelPath,
                  settings: load.settings,
                  mmprojPath: load.mmprojPath,
                  adapters: load.adapters,
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
      if (ram != null && result['ramBudgetMb'] is num) {
        result['ramBudgetMb'] =
            (result['ramBudgetMb'] as num) +
            (result['ramAvailableMb'] as num) -
            ram;
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
        result['ramPagedMb'] = actual['memoryPagedMb'] ?? e['ramPagedMb'];
        result['loadedAdmission'] = true;
      }
      return result;
    } catch (_) {
      return {...e, 'modelLoaded': true};
    }
  }
}

String _plain(Object e) {
  final text = '$e';
  final colon = text.indexOf(': ');
  return text.startsWith('Bad state') || text.startsWith('InferenceException')
      ? text.substring(colon + 2)
      : text;
}

String _tokens(int n) => n >= 1024 && n % 1024 == 0 ? '${n ~/ 1024}K' : '$n';

String _gb(num mb) => (mb / 1024).toStringAsFixed(1);

/// What the bridge measured: VRAM and RAM bars, how many layers are on
/// the card, and any context cut.
class _EstimatePanel extends StatelessWidget {
  final Map<String, dynamic>? estimate;
  final String? error;
  final bool measuring;

  /// The plan shown is for the previous settings; a new one is on its way.
  final bool stale;
  final int requestedContext;

  /// The context (KV) cache at the planned length, in MiB.
  final num kvMb;
  const _EstimatePanel({
    this.kvMb = 0,
    required this.estimate,
    required this.error,
    required this.measuring,
    this.stale = false,
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
      final provisional = e['analytical'] == true;
      final needMb = (e['vramNeedMb'] as num?) ?? 0;
      final freeMb = e['vramFreeMb'] as num?;
      // A full card reads 0 MB free, which still spills. The instant
      // estimate puts every layer on the card before the bridge's fit, so
      // only a measured plan can say it spills.
      final spills =
          !provisional &&
          onCard &&
          gpu > 0 &&
          freeMb != null &&
          needMb > freeMb;
      final uncertain =
          e['modelLoaded'] == true && e['loadedAdmission'] != true;
      final creditedFits =
          ((e['ramNeedMb'] as num?) ?? 0) <=
              ((e['ramAvailableMb'] as num?) ?? 0) &&
          needMb <= (freeMb ?? 0);
      if (provisional && !onCard) {
        // Capacity is unknown until a hardware probe returns.
      } else if (uncertain && creditedFits && gpu == 0) {
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
      // Where the weights go (owner 2026-11-16: "RAM 0.1 of 13.9 GB" next
      // to "+16.0 GB paged from disk" said nothing). Memory-mapped host
      // weights stay in free RAM; what does not fit is read from disk.
      final experts = e['gpuExpertsOnCpu'] == true;
      final paged = (e['ramPagedMb'] as num?) ?? 0;
      final ramFree0 = e['ramAvailableMb'] as num?;
      final ramNeed0 = (e['ramNeedMb'] as num?) ?? 0;
      final resident = ramFree0 == null
          ? paged
          : (ramFree0 - ramNeed0).clamp(0, paged);
      final fromDisk = paged - resident;
      if (paged > 0 && resident >= 52) {
        notes.add((
          experts ? Icons.hub_outlined : Icons.memory_rounded,
          experts
              ? t.desktopLoadSettingsExpertsInRam(_gb(resident))
              : t.desktopLoadSettingsWeightsInRam(_gb(resident)),
          c.textMuted,
        ));
      } else if (experts) {
        notes.add((
          Icons.hub_outlined,
          t.desktopLoadSettingsExperts,
          c.textMuted,
        ));
      }
      if (fromDisk >= 103) {
        notes.add((
          Icons.storage_rounded,
          t.desktopLoadSettingsFromDisk(_gb(fromDisk)),
          c.warning,
        ));
      }
      if (kvMb >= 52) {
        notes.add((
          Icons.view_stream_outlined,
          t.desktopLoadSettingsKvCache(_gb(kvMb)),
          c.textMuted,
        ));
      }
      // RAM the load would leave short: the same budget the bridge admits
      // against (free RAM minus a reserve for the desktop), so the panel
      // warns before a load is refused or the PC starts paging.
      final ramNeed = (e['ramNeedMb'] as num?) ?? 0;
      final ramFree = e['ramAvailableMb'] as num?;
      final ramBudget =
          (e['ramBudgetMb'] as num?) ??
          (ramFree == null
              ? null
              : ramFree -
                    math.max(1024, ((e['ramTotalMb'] as num?) ?? ramFree) / 8));
      if (!provisional &&
          ramBudget != null &&
          ramNeed > ramBudget &&
          !(uncertain && creditedFits)) {
        notes.add((
          Icons.warning_amber_rounded,
          t.desktopLoadSettingsRamShort(
            (math.max(ramNeed - ramBudget, 103) / 1024).toStringAsFixed(1),
          ),
          c.danger,
        ));
      }
      if (e['memoryWarning'] == 'weightsExceedFreeRam') {
        notes.add((
          Icons.storage_rounded,
          t.desktopLoadSettingsWeightsPaging,
          c.warning,
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
              if (stale)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    t.desktopLoadSettingsRecalculating,
                    key: const Key('estimate-recalculating'),
                    style: context.text.caption.copyWith(color: c.textMuted),
                  ),
                ),
              if (measuring || stale)
                const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedOpacity(
            opacity: stale ? 0.45 : 1,
            duration: const Duration(milliseconds: 150),
            child: BlurSwitcher(
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
                    if (e['vramTotalMb'] != null ||
                        ((e['vramNeedMb'] as num?) ?? 0) > 0)
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
                      detail: _mappedMb(e) >= 52
                          ? t.desktopLoadSettingsRamMapped(_gb(_mappedMb(e)))
                          : '',
                      need: (e['ramNeedMb'] as num?) ?? 0,
                      mapped: _mappedMb(e),
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
                                style: context.text.small.copyWith(
                                  color: color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Memory-mapped weights that stay in free RAM next to what the load
/// needs; Windows can drop them under pressure and read them back.
num _mappedMb(Map<String, dynamic> e) {
  final paged = (e['ramPagedMb'] as num?) ?? 0;
  final free = e['ramAvailableMb'] as num?;
  if (free == null) return 0;
  return (free - ((e['ramNeedMb'] as num?) ?? 0)).clamp(0, paged);
}

class _Meter extends StatelessWidget {
  final String label, detail;
  final num need, free;

  /// Memory-mapped weights shown as a lighter segment after [need].
  final num mapped;
  const _Meter({
    required this.label,
    required this.detail,
    required this.need,
    this.mapped = 0,
    required this.free,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final share = free <= 0 ? 1.0 : (need / free).clamp(0.0, 1.0).toDouble();
    final mappedShare = free <= 0
        ? 0.0
        : ((need + mapped) / free).clamp(0.0, 1.0).toDouble();
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
                  free > 0
                      ? context.l10n.desktopLoadSettingsUsage(
                          _gb(need + mapped),
                          _gb(free),
                        )
                      : '${_gb(need + mapped)} GB',
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
          Stack(
            children: [
              if (mapped > 0)
                TweenAnimationBuilder<double>(
                  tween: Tween(end: mappedShare),
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => LinearProgressIndicator(
                    value: v,
                    minHeight: 6,
                    borderRadius: AppDesign.radius(3),
                    color: c.accent.fade(0.35),
                    backgroundColor: c.text.fade(0.08),
                  ),
                ),
              TweenAnimationBuilder<double>(
                tween: Tween(end: share),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  borderRadius: AppDesign.radius(3),
                  color: over ? c.danger : c.accent,
                  backgroundColor: mapped > 0
                      ? Colors.transparent
                      : c.text.fade(0.08),
                ),
              ),
            ],
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
