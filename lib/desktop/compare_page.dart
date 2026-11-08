import '../core/platform/desktop_preferences.dart';
import 'model_visibility.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/design/app_dialog.dart';
import 'history_store.dart';
import '../core/errors/exceptions.dart';
import '../core/l10n/l10n.dart';
import '../core/providers/shared_providers.dart';
import '../features/chat/domain/entities/chat_message.dart';
import '../features/chat/presentation/widgets/chat_bubble.dart';
import '../features/models/domain/entities/model_info.dart';
import '../features/models/presentation/providers/model_manager_provider.dart';
import '../inference/engine/llama_engine.dart';

class DesktopComparePage extends ConsumerStatefulWidget {
  const DesktopComparePage({super.key});

  @override
  ConsumerState<DesktopComparePage> createState() => _DesktopComparePageState();
}

class _CompareColumn {
  String? modelId;
  LlamaEngine? engine;
  bool ownEngine = false;
  bool loading = false;
  bool generating = false;
  double? progress;
  String answer = '';
  String? error;
  Map<String, dynamic> metrics = const {};
  Duration? elapsed;
  StreamSubscription<double?>? progressSubscription;
  Future<void>? task;
  int epoch = 0;
}

class _DesktopComparePageState extends ConsumerState<DesktopComparePage> {
  final _prompt = TextEditingController();
  final _system = TextEditingController();
  final _columns = [_CompareColumn(), _CompareColumn()];
  bool _sideBySide = false;
  bool _showSystem = false;
  bool _running = false;
  bool _viewingHistory = false;
  bool _showHistory = false;
  final _historyScroll = ScrollController();
  int _runEpoch = 0;
  Future<void>? _activeRun;

  @override
  void dispose() {
    _historyScroll.dispose();
    _runEpoch++;
    for (final column in _columns) {
      column.epoch++;
      if (column.loading || column.generating) column.engine?.cancel();
      unawaited(_release(column));
    }
    _prompt.dispose();
    _system.dispose();
    super.dispose();
  }

  Future<void> _release(_CompareColumn column) async {
    final subscription = column.progressSubscription;
    column.progressSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final engine = column.engine;
    final own = column.ownEngine;
    column.engine = null;
    column.ownEngine = false;
    if (!own || engine == null) return;
    try {
      if (column.task != null) await column.task;
      if (engine.isLoaded) await engine.unload();
    } catch (_) {
      // A failed load can leave no model to unload.
    } finally {
      engine.dispose();
    }
  }

  Future<void> _stop() async {
    _runEpoch++;
    for (final column in _columns) {
      if (column.loading || column.generating) column.engine?.cancel();
    }
    await Future.wait([
      for (final column in _columns)
        if (column.task != null) column.task!,
    ]);
    await _activeRun;
    if (mounted) setState(() => _running = false);
  }

  Future<void> _select(int index, String? id) async {
    await _stop();
    final column = _columns[index];
    column.epoch++;
    if (column.loading || column.generating) column.engine?.cancel();
    await _release(column);
    if (!mounted) return;
    setState(() {
      column.modelId = id;
      column.answer = '';
      column.error = null;
      column.metrics = const {};
      column.elapsed = null;
      column.progress = null;
      column.loading = false;
      column.generating = false;
    });
  }

  Future<void> _run() async {
    if (_running) return;
    final task = _executeRun();
    _activeRun = task;
    try {
      await task;
    } finally {
      if (_activeRun == task) _activeRun = null;
    }
  }

  Future<void> _executeRun() async {
    if (_viewingHistory) setState(() => _viewingHistory = false);
    final prompt = _prompt.text.trim();
    final system = _system.text.trim();
    if (prompt.isEmpty || _running) return;
    final catalog = ref.read(modelManagerProvider).catalog;
    final chosen = [
      for (final column in _columns)
        catalog
            .where((m) => m.id == column.modelId && m.isDownloaded)
            .firstOrNull,
    ];
    if (chosen.any((m) => m == null) || chosen[0]!.id == chosen[1]!.id) return;
    final historyStore = ref.read(compareHistoryStoreProvider);
    final run = ++_runEpoch;
    final parallel = _sideBySide;
    final createdAt = DateTime.now();
    setState(() {
      _viewingHistory = false;
      _running = true;
      for (final column in _columns) {
        column.answer = '';
        column.error = null;
        column.metrics = const {};
        column.elapsed = null;
      }
    });
    try {
      if (_sideBySide) {
        await Future.wait([
          _answer(_columns[0], chosen[0]!, prompt, system, run),
          _answer(_columns[1], chosen[1]!, prompt, system, run),
        ]);
      } else {
        for (var index = 0; index < _columns.length; index++) {
          if (_runEpoch != run) break;
          // A previous run (including parallel mode) may retain the other model.
          final other = _columns[1 - index];
          if (other.ownEngine) await _release(other);
          if (_runEpoch != run) break;
          await _answer(_columns[index], chosen[index]!, prompt, system, run);
        }
      }
    } finally {
      // Snapshot before allowing another run or history selection to mutate panes.
      final entry = HistoryEntry(
        createdAt: createdAt,
        data: {
          'prompt': prompt,
          'systemPrompt': system,
          'mode': parallel ? 'parallel' : 'sequential',
          'interrupted': _runEpoch != run,
          'sides': [
            for (var i = 0; i < _columns.length; i++)
              {
                'modelId': chosen[i]!.id,
                'answer': _columns[i].answer,
                'metrics': _columns[i].metrics,
                'totalMs': _columns[i].elapsed?.inMilliseconds,
                'error': _columns[i].error,
              },
          ],
        },
      );
      try {
        await historyStore.save(entry);
        if (mounted) ref.invalidate(compareHistoryProvider);
      } catch (e) {
        _historyError(e);
      }
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _answer(
    _CompareColumn column,
    ModelInfo model,
    String prompt,
    String system,
    int run,
  ) async {
    final epoch = column.epoch;
    final desiredSettings = ref
        .read(modelManagerProvider.notifier)
        .servedSettings(model);
    Future<void> work() async {
      final totalWatch = Stopwatch()..start();
      LlamaEngine? engine = column.engine;
      try {
        final chat = ref.read(llamaEngineProvider);
        if (engine == chat &&
            (chat.isBusy ||
                ref.read(sessionBusyProvider) ||
                ref.read(modelManagerProvider).loadedModelId != model.id)) {
          column.engine = null;
          engine = null;
        }
        if (engine == null) {
          final chatModel = ref.read(modelManagerProvider).loadedModelId;
          if (chatModel == model.id &&
              chat.isLoaded &&
              !chat.isBusy &&
              !ref.read(sessionBusyProvider) &&
              !_columns.any((c) => c != column && c.engine == chat)) {
            engine = chat;
            column.ownEngine = false;
          } else {
            engine = ref.read(engineFactoryProvider)();
            column.ownEngine = true;
            column.loading = true;
            column.progressSubscription = engine.loadProgressChanges.listen((
              value,
            ) {
              if (mounted && column.epoch == epoch) {
                setState(() => column.progress = value);
              }
            });
            column.engine = engine;
            if (mounted) setState(() {});
          }
          column.engine = engine;
        }
        if (column.ownEngine) {
          column.loading = true;
          if (mounted) setState(() {});
          // The engine compares the canonical native load configuration and
          // preserves its runtime and caches for unchanged or sampling settings.
          await ref
              .read(modelManagerProvider.notifier)
              .loadServed(model, engine);
          column.loading = false;
          if (mounted) setState(() {});
        }
        if (_runEpoch != run || column.epoch != epoch || !mounted) return;
        if (engine.isBusy) {
          throw StateError(context.l10n.desktopCompareBusy);
        }
        column.generating = true;
        setState(() {});
        final messages = <Map<String, Object>>[
          if (system.isNotEmpty) {'role': 'system', 'content': system},
          {'role': 'user', 'content': prompt},
        ];
        final watch = Stopwatch()..start();
        await for (final chunk in engine.generate(
          messages: messages,
          fallbackTemplate: model.family.fallbackTemplate,
          settings: desiredSettings,
        )) {
          if (_runEpoch != run || column.epoch != epoch || !mounted) break;
          setState(() => column.answer += chunk);
        }
        watch.stop();
        if (mounted && column.epoch == epoch) {
          setState(() {
            column.metrics = Map.of(engine!.metrics);
            column.elapsed = watch.elapsed;
          });
        }
      } catch (error) {
        if (column.epoch == epoch &&
            column.ownEngine &&
            engine != null &&
            !engine.isLoaded) {
          final subscription = column.progressSubscription;
          if (subscription != null) unawaited(subscription.cancel());
          column.progressSubscription = null;
          column.engine = null;
          column.ownEngine = false;
          engine.dispose();
        }
        if (mounted && column.epoch == epoch && _runEpoch == run) {
          setState(
            () => column.error = error is AppException
                ? error.message
                : error.toString(),
          );
        }
      } finally {
        totalWatch.stop();
        if (mounted && column.epoch == epoch) {
          setState(() {
            column.elapsed ??= totalWatch.elapsed;
            column.loading = false;
            column.generating = false;
            column.progress = null;
          });
        }
      }
    }

    final task = work();
    column.task = task;
    await task;
    if (column.task == task) column.task = null;
  }

  void _historyError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.historyFailed('$error'))),
    );
  }

  Future<void> _restoreHistory(HistoryEntry entry) async {
    if (_running) return;
    for (final column in _columns) {
      await _release(column);
    }
    if (!mounted) return;
    setState(() {
      _viewingHistory = true;
      _prompt.text = entry.data['prompt'] as String;
      _system.text = entry.data['systemPrompt'] as String;
      _showSystem = _system.text.isNotEmpty;
      _sideBySide = entry.data['mode'] == 'parallel';
      final sides = entry.data['sides'] as List;
      for (var i = 0; i < 2; i++) {
        final side = sides[i] as Map;
        final column = _columns[i];
        column.modelId = side['modelId'] as String;
        column.answer = side['answer'] as String;
        column.error = side['error'] as String?;
        column.metrics = Map<String, dynamic>.from(side['metrics'] as Map);
        column.elapsed = side['totalMs'] == null
            ? null
            : Duration(milliseconds: side['totalMs'] as int);
      }
    });
  }

  Widget _historyPanel() {
    final t = context.l10n;
    final c = context.colors;
    final names = {
      for (final m in ref.watch(modelManagerProvider).catalog)
        m.id: m.displayName,
    };
    final material = MaterialLocalizations.of(context);
    String when(DateTime at) {
      final local = at.toLocal();
      return '${material.formatShortDate(local)} '
          '${material.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    }

    Future<void> clear() async {
      if (!await confirmAction(
        context,
        title: t.historyClear,
        message: t.historyClearConfirm,
        confirmLabel: t.historyClear,
        destructive: true,
      )) {
        return;
      }
      try {
        await ref.read(compareHistoryStoreProvider).clear();
        ref.invalidate(compareHistoryProvider);
      } catch (e) {
        _historyError(e);
      }
    }

    Future<void> delete(String id) async {
      if (!await confirmAction(
        context,
        title: t.historyDelete,
        message: t.historyDeleteConfirm,
        confirmLabel: t.historyDelete,
        destructive: true,
      )) {
        return;
      }
      try {
        await ref.read(compareHistoryStoreProvider).delete(id);
        ref.invalidate(compareHistoryProvider);
      } catch (e) {
        _historyError(e);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppDesign.sm),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(t.historyTitle, style: context.text.title),
                  ),
                  TextButton.icon(
                    onPressed: _running ? null : clear,
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    label: Text(t.historyClear),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: c.hairline),
            SizedBox(
              height: 180,
              child: ref
                  .watch(compareHistoryProvider)
                  .when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text(t.historyFailed('$e'))),
                    data: (items) => items.isEmpty
                        ? Center(
                            child: Text(
                              t.historyEmpty,
                              style: context.text.small.copyWith(
                                color: c.textMuted,
                              ),
                            ),
                          )
                        : Scrollbar(
                            controller: _historyScroll,
                            thumbVisibility: true,
                            child: ListView.builder(
                              controller: _historyScroll,
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final item = items[index];
                                final models = (item.data['sides'] as List)
                                    .map((s) {
                                      final id = s['modelId'] as String?;
                                      return names[id] ?? id ?? '';
                                    })
                                    .join('  vs  ');
                                return ListTile(
                                  dense: true,
                                  enabled: !_running,
                                  title: Text(
                                    item.data['prompt'] as String,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    '$models · ${when(item.createdAt)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.text.small.copyWith(
                                      color: c.textMuted,
                                    ),
                                  ),
                                  onTap: _running
                                      ? null
                                      : () => _restoreHistory(item),
                                  trailing: IconButton(
                                    tooltip: t.historyDelete,
                                    iconSize: 18,
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: _running
                                        ? null
                                        : () => delete(item.id),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final c = context.colors;
    final models = ref
        .watch(modelManagerProvider)
        .catalog
        .where(
          (m) =>
              m.isDownloaded &&
              desktopModelVisible(
                m,
                advanced: ref.watch(desktopPreferencesProvider).advanced,
              ),
        )
        .toList();
    final ready =
        _columns.every((column) => column.modelId != null) &&
        _columns[0].modelId != _columns[1].modelId;
    return Padding(
      padding: const EdgeInsets.all(AppDesign.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.desktopCompareTitle,
                  style: context.text.headline,
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _showHistory = !_showHistory),
                icon: const Icon(Icons.history),
                label: Text(t.historyTitle),
              ),
            ],
          ),
          if (_viewingHistory)
            Text(t.historyReadOnly, style: context.text.small),
          if (_showHistory) _historyPanel(),
          const SizedBox(height: 16),
          TextField(
            key: const Key('desktopComparePrompt'),
            controller: _prompt,
            readOnly: _viewingHistory || _running,
            maxLines: 3,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: t.desktopComparePrompt),
          ),
          TextButton.icon(
            onPressed: () => setState(() => _showSystem = !_showSystem),
            icon: Icon(_showSystem ? Icons.expand_less : Icons.expand_more),
            label: Text(t.desktopCompareSystem),
          ),
          if (_showSystem)
            TextField(
              controller: _system,
              readOnly: _viewingHistory || _running,
              maxLines: 2,
              decoration: InputDecoration(labelText: t.desktopCompareSystem),
            ),
          Row(
            children: [
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(t.desktopCompareSequential),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(t.desktopCompareParallel),
                  ),
                ],
                selected: {_sideBySide},
                onSelectionChanged: _running || _viewingHistory
                    ? null
                    : (v) => setState(() => _sideBySide = v.first),
              ),
              const SizedBox(width: 16),
              if (_running)
                OutlinedButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.stop_rounded),
                  label: Text(t.desktopCompareStop),
                )
              else
                FilledButton.icon(
                  onPressed: ready && _prompt.text.trim().isNotEmpty
                      ? _run
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(t.desktopCompareRun),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < 2; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: _column(context, i, models, c)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _column(
    BuildContext context,
    int index,
    List<ModelInfo> models,
    AppColors c,
  ) {
    final t = context.l10n;
    final column = _columns[index];
    final model = models.where((m) => m.id == column.modelId).firstOrNull;
    final m = column.metrics;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border.all(color: c.hairline),
        borderRadius: AppDesign.radius(AppDesign.rLg),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: c.surface,
                      border: Border.all(color: c.hairline),
                      borderRadius: AppDesign.radius(AppDesign.rFull),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          key: Key('desktopCompareModel$index'),
                          isExpanded: true,
                          borderRadius: AppDesign.radius(AppDesign.rMd),
                          hint: Text(
                            _viewingHistory
                                ? column.modelId ?? t.desktopComparePickModel
                                : t.desktopComparePickModel,
                          ),
                          value: model?.id,
                          items: [
                            for (final item in models)
                              DropdownMenuItem(
                                value: item.id,
                                enabled: item.id != _columns[1 - index].modelId,
                                child: Text(
                                  '${item.displayName} · ${item.quantLabel} · ${item.sizeLabel}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _running || _viewingHistory
                              ? null
                              : (id) => _select(index, id),
                        ),
                      ),
                    ),
                  ),
                ),
                if (column.ownEngine)
                  IconButton(
                    tooltip: t.desktopCompareUnload,
                    onPressed: _viewingHistory
                        ? null
                        : () => _select(index, null),
                    icon: const Icon(Icons.eject_outlined),
                  ),
                IconButton(
                  tooltip: t.desktopCompareCopy,
                  onPressed: column.answer.isEmpty
                      ? null
                      : () => Clipboard.setData(
                          ClipboardData(text: column.answer),
                        ),
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ),
          if (column.loading) ...[
            LinearProgressIndicator(value: column.progress),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                column.progress == null
                    ? t.desktopCompareLoading
                    : '${t.desktopCompareLoading} ${(column.progress! * 100).round()}%',
              ),
            ),
          ],
          if (column.error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(column.error!, style: TextStyle(color: c.danger)),
            ),
          Expanded(
            child: SingleChildScrollView(
              child: column.answer.isEmpty
                  ? const SizedBox.shrink()
                  : ChatBubble(
                      streaming: column.generating,
                      modelName: model?.displayName ?? column.modelId,
                      message: ChatMessage(
                        id: 'compare-$index',
                        role: ChatRole.assistant,
                        content: column.answer,
                        timestamp: DateTime.now(),
                      ),
                    ),
            ),
          ),
          if (column.elapsed != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: DefaultTextStyle(
                style: context.text.small,
                child: Wrap(
                  spacing: 12,
                  children: [
                    Text(
                      '${t.desktopCompareFirstToken}: ${m['firstTokenMs'] is num ? (m['firstTokenMs'] as num).round() : '–'} ms',
                    ),
                    Text(
                      '${t.desktopCompareSpeed}: ${m['tokensPerSecond'] is num ? (m['tokensPerSecond'] as num).toStringAsFixed(1) : '–'} tok/s',
                    ),
                    Text('${t.desktopCompareTokens}: ${m['tokens'] ?? '–'}'),
                    Text(
                      '${t.desktopCompareTotal}: ${(column.elapsed!.inMilliseconds / 1000).toStringAsFixed(2)} s',
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
