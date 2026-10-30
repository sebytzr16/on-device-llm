import '../core/platform/desktop_preferences.dart';
import 'model_visibility.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
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
  int _runEpoch = 0;

  @override
  void dispose() {
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
    final run = ++_runEpoch;
    setState(() {
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
        await _answer(_columns[0], chosen[0]!, prompt, system, run);
        if (_runEpoch == run) {
          await _answer(_columns[1], chosen[1]!, prompt, system, run);
        }
      }
    } finally {
      if (mounted && _runEpoch == run) setState(() => _running = false);
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
    Future<void> work() async {
      LlamaEngine? engine = column.engine;
      try {
        final chat = ref.read(llamaEngineProvider);
        if (engine == chat &&
            (chat.isBusy ||
                ref.read(modelManagerProvider).loadedModelId != model.id)) {
          column.engine = null;
          engine = null;
        }
        if (engine == null) {
          final chatModel = ref.read(modelManagerProvider).loadedModelId;
          if (chatModel == model.id &&
              chat.isLoaded &&
              !chat.isBusy &&
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
            await ref
                .read(modelManagerProvider.notifier)
                .loadServed(model, engine);
            column.loading = false;
            if (mounted) setState(() {});
          }
          column.engine = engine;
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
          settings: ref
              .read(modelManagerProvider.notifier)
              .servedSettings(model),
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
        if (mounted && column.epoch == epoch) {
          setState(() {
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
          Text(t.desktopCompareTitle, style: context.text.headline),
          const SizedBox(height: 16),
          TextField(
            key: const Key('desktopComparePrompt'),
            controller: _prompt,
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
                onSelectionChanged: _running
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
                          hint: Text(t.desktopComparePickModel),
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
                          onChanged: _running
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
                    onPressed: () => _select(index, null),
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
                      modelName: model?.displayName,
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
