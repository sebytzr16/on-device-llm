// Physical release-process recovery drill; uses only the isolated .smoke app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondevice_llm/core/providers/shared_providers.dart';
import 'package:ondevice_llm/core/theme/app_theme.dart';
import 'package:ondevice_llm/data/local/database/app_database.dart';
import 'package:ondevice_llm/features/attachments/data/attachment_store.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/chat/domain/chat_draft_store.dart';
import 'package:ondevice_llm/features/goals/goal_runner.dart';
import 'package:ondevice_llm/features/goals/presentation/goal_provider.dart';
import 'package:ondevice_llm/features/goals/presentation/goals_page.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';
import 'package:ondevice_llm/features/settings/presentation/providers/settings_provider.dart';
import 'package:ondevice_llm/inference/engine/llama_engine.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'quality_smoke.dart' show QualitySettings, QualityModels;

const _runId = String.fromEnvironment('QUALITY_RUN_ID', defaultValue: 'manual');
void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _log(String marker, Object value) {
  // ignore: avoid_print
  print('$marker ${jsonEncode(value)}');
}

Future<void> _run() async {
  final prefs = await SharedPreferences.getInstance();
  final key = 'quality_recovery_$_runId';
  final phase = prefs.getString(key);
  if (phase == 'starting' || phase == 'continuing' || phase == 'complete') {
    _log('QUALITY_PROGRESS', {'existingProbe': phase});
    return;
  }
  final restarting = phase == 'recover';
  await prefs.setString(key, restarting ? 'continuing' : 'starting');
  if (!restarting) await prefs.remove('active_goal_v2');
  final external = (await getExternalStorageDirectory())!;
  Future<void> save(String name, Object data) async {
    await File(
      '${external.path}/$name.json',
    ).writeAsString(jsonEncode(data), flush: true);
  }

  final db = AppDatabase();
  final engine = LlamaEngine(
    cacheDirectory: () async => (await getApplicationCacheDirectory()).path,
  );
  final container = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      llamaEngineProvider.overrideWithValue(engine),
      settingsProvider.overrideWith(QualitySettings.new),
      modelManagerProvider.overrideWith(QualityModels.new),
    ],
  );
  // Leave the real Goal UI available for checking model and evidence displays.
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const GoalsPage()),
    ),
  );
  final controller = container.read(goalProvider.notifier);
  await controller.ready;
  if (!restarting) {
    final directory = await AttachmentStore.directory();
    final attachment = File('${directory.path}/quality-recovery.txt');
    await attachment.writeAsString(
      'Process-death draft attachment.',
      flush: true,
    );
    await ChatDraftStore().save(
      'quality-recovery',
      ChatDraft(
        text: 'Unsaved composer text survives a process restart.',
        attachments: [
          Attachment(
            id: 'quality-recovery',
            kind: AttachmentKind.document,
            name: 'quality-recovery.txt',
            mime: 'text/plain',
            path: attachment.path,
            sizeBytes: await attachment.length(),
            text: 'Process-death draft attachment.',
          ),
        ],
      ),
    );
    var marked = false;
    final listener = container.listen(goalProvider, (_, next) {
      if (next == null) return;
      _log('QUALITY_PROGRESS', {
        'phase': '${next.status.name}/${next.phase.name}',
        'steps': next.steps,
        'sources': next.sources.length,
      });
      if (marked ||
          next.status != GoalStatus.running ||
          next.done < 1 ||
          next.sources.isEmpty) {
        return;
      }
      marked = true;
      unawaited(
        () async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
          await prefs.reload();
          final raw = prefs.getString('active_goal_v2');
          _require(raw != null, 'Checkpoint was not saved.');
          final checkpoint = jsonDecode(raw!) as Map<String, dynamic>;
          _require(
            (checkpoint['steps'] as num) > 0 &&
                (checkpoint['sources'] as List).isNotEmpty,
            'Checkpoint lost research evidence.',
          );
          await save('quality-recovery-before', checkpoint);
          await prefs.setString(key, 'recover');
          _log('QUALITY_RECOVERY_READY', {
            'steps': checkpoint['steps'],
            'status': checkpoint['status'],
          });
        }().catchError(
          (Object error) => _log('QUALITY_FAILED', {'error': '$error'}),
        ),
      );
    });
    try {
      await controller.start(
        const GoalSpec(
          objective:
              'Compare the Nikon Z30 and original Sony ZV-E10 effective sensor resolution.',
          successCriteria:
              'State the Nikon Z30 effective sensor megapixels with a manufacturer citation.\nState the original Sony ZV-E10 effective sensor megapixels with a manufacturer citation.',
          searchGuidance:
              'Use the exact original cameras, not the ZV-E10 II. Compare only effective still-image resolution, not total sensor pixels. Keep the report concise.',
          specialization: GoalSpecialization.product,
          maxSteps: 4,
          maxDuration: Duration(minutes: 15),
          maxTokens: 100000,
          maxToolCalls: 30,
        ),
      );
      if (container.read(goalProvider)!.awaitingInputSince != null) {
        await controller.answerClarifications(const {});
      }
    } finally {
      listener.close();
    }
    if (!marked) {
      throw StateError('No persisted research checkpoint to interrupt.');
    }
    _log('QUALITY_PROGRESS', {'waitingForProcessRestart': true});
    return;
  }
  final restored = container.read(goalProvider)!;
  final before =
      jsonDecode(
            await File(
              '${external.path}/quality-recovery-before.json',
            ).readAsString(),
          )
          as Map<String, dynamic>;
  _require(
    restored.status == GoalStatus.paused,
    'Interrupted running Goal did not restore paused.',
  );
  _require(
    restored.steps >= (before['steps'] as num) &&
        restored.sources.length >= (before['sources'] as List).length,
    'Process restart lost steps or sources.',
  );
  _require(
    restored.usedTokens >= (before['usedTokens'] as num) &&
        restored.usedToolCalls >= (before['usedToolCalls'] as num),
    'Process restart reset usage.',
  );
  _require(
    restored.spec.completionTarget == 0.85 &&
        restored.spec.searchGuidance.contains('original cameras'),
    'Goal specification was lost.',
  );
  _require(
    controller.chatId != null &&
        (await db.getMessages(controller.chatId!)).isNotEmpty,
    'Goal chat was lost.',
  );
  final draft = await ChatDraftStore().read('quality-recovery');
  _require(
    draft.text == 'Unsaved composer text survives a process restart.' &&
        draft.attachments.length == 1 &&
        await File(draft.attachments.single.path).exists(),
    'Composer draft or attachment was lost.',
  );
  await save(
    'quality-recovery-restored',
    GoalNotifier.encode(restored, chatId: controller.chatId),
  );
  _log('QUALITY_RECOVERY_RESTORED', {
    'steps': restored.steps,
    'sources': restored.sources.length,
    'tokens': restored.usedTokens,
    'draft': true,
  });
  var pauseRequested = false;
  final listener = container.listen(goalProvider, (_, next) {
    if (next == null) return;
    _log('QUALITY_PROGRESS', {
      'phase': '${next.status.name}/${next.phase.name}',
      'steps': next.steps,
      'sources': next.sources.length,
    });
    if (!pauseRequested &&
        next.status == GoalStatus.running &&
        next.phase == GoalPhase.checking) {
      pauseRequested = true;
      controller.pause();
    }
  });
  try {
    await controller.continueGoal();
  } finally {
    listener.close();
  }
  if (pauseRequested &&
      container.read(goalProvider)!.status == GoalStatus.paused) {
    await save(
      'quality-recovery-paused',
      GoalNotifier.encode(
        container.read(goalProvider)!,
        chatId: controller.chatId,
      ),
    );
    _log('QUALITY_RECOVERY_PAUSED', {
      'steps': container.read(goalProvider)!.steps,
    });
    await controller.continueGoal();
  }
  final goal = container.read(goalProvider)!;
  await save(
    'quality-recovery-final',
    GoalNotifier.encode(goal, chatId: controller.chatId),
  );
  _require(goal.status != GoalStatus.failed, goal.error ?? 'Goal failed.');
  _require(
    goal.status != GoalStatus.completed || goal.spec.meetsTarget(goal.criteria),
    'Goal completed without supported requirements.',
  );
  _require(
    goal.usedTokens >= restored.usedTokens &&
        goal.usedToolCalls >= restored.usedToolCalls,
    'Continuation reset cumulative usage.',
  );
  _log('QUALITY_OK', {
    'status': goal.status.name,
    'coverage': goal.spec.coverage(goal.criteria),
    'reportChars': goal.report.length,
    'steps': goal.steps,
    'sources': goal.sources.length,
    'tokens': goal.usedTokens,
    'pauseRequested': pauseRequested,
  });
  await prefs.setString(key, 'complete');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('Goal recovery probe'))));
  unawaited(
    _run().catchError((Object error, StackTrace stack) {
      _log('QUALITY_FAILED', {'error': '$error', 'stack': '$stack'});
    }),
  );
}
