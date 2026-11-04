import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../data/local/database/app_database.dart';
import '../settings/domain/entities/inference_settings.dart';

const agentWebDecisionKey = '_agentWebAllowed';

/// Host metadata stays outside the settings cascade and survives settings edits.
class AgentWebDecisions {
  final AppDatabase db;
  AgentWebDecisions(this.db);

  Future<bool?> read(String chatId) async {
    final chat = await db.getChat(chatId);
    if (chat == null) return null;
    final value = decode(chat.overridesJson)[agentWebDecisionKey];
    return value is bool ? value : null;
  }

  Future<void> write(String chatId, bool allow) => db.transaction(() async {
    final chat = await db.getChat(chatId);
    if (chat == null) throw StateError('Chat no longer exists');
    await (db.update(db.chats)..where((t) => t.id.equals(chatId))).write(
      ChatsCompanion(
        overridesJson: Value(
          jsonEncode({
            ...decode(chat.overridesJson),
            agentWebDecisionKey: allow,
          }),
        ),
      ),
    );
  });

  static Map<String, dynamic> decode(String raw) {
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, dynamic>.from(value) : {};
    } catch (_) {
      return {};
    }
  }
}

class AgentWebQuestion {
  final String? description;
  AgentWebQuestion({this.description});
  final answer = Completer<bool>();
  int waiters = 0;
  Future<bool?>? stored;
  Future<void>? saving;
}

/// Every waiter owns its cancellation; one cancelled agent cannot answer for another.
class AgentWebApproval {
  final void Function(Map<String, AgentWebQuestion>) changed;
  final _pending = <String, AgentWebQuestion>{};
  bool _disposed = false;
  final _stop = CancelToken();
  AgentWebApproval({required this.changed});

  Future<bool> request({
    required String chatId,
    required AgentWebAccess mode,
    required Future<bool?> Function() read,
    required Future<void> Function(bool) save,
    CancelToken? cancel,
    String? description,
  }) async {
    if (cancel?.isCancelled == true) throw cancel!.cancelError!;
    if (_disposed) return false;
    if (mode != AgentWebAccess.askOnce) {
      return mode == AgentWebAccess.alwaysAllow;
    }
    final question = _pending.putIfAbsent(
      chatId,
      () => AgentWebQuestion(description: description),
    );
    question.waiters++;
    try {
      // Read inside the shared question: a second caller joins before any I/O.
      final stored = await Future.any<bool?>([
        question.stored ??= read(),
        _stop.whenCancel.then((error) => throw error),
        if (cancel != null) cancel.whenCancel.then((error) => throw error),
      ]);
      if (cancel?.isCancelled == true) throw cancel!.cancelError!;
      if (stored != null && !question.answer.isCompleted) {
        question.answer.complete(stored);
      }
      if (!question.answer.isCompleted) changed(Map.unmodifiable(_pending));
      final allowed = await Future.any<bool>([
        question.answer.future,
        _stop.whenCancel.then((error) => throw error),
        if (cancel != null) cancel.whenCancel.then((error) => throw error),
      ]);
      if (cancel?.isCancelled == true) throw cancel!.cancelError!;
      // Persistence completes before any network call can begin.
      if (stored == null) await (question.saving ??= save(allowed));
      if (cancel?.isCancelled == true) throw cancel!.cancelError!;
      return allowed;
    } finally {
      question.waiters--;
      if (question.waiters == 0 && identical(_pending[chatId], question)) {
        _pending.remove(chatId);
        if (!_disposed) changed(Map.unmodifiable(_pending));
      }
    }
  }

  void answer(String chatId, bool allow) {
    final question = _pending[chatId];
    if (question != null && !question.answer.isCompleted) {
      question.answer.complete(allow);
    }
  }

  void dispose() {
    _disposed = true;
    _stop.cancel('disposed');
    _pending.clear();
  }
}

final agentWebQuestionsProvider = StateProvider<Map<String, AgentWebQuestion>>(
  (ref) => {},
);
final agentWebApprovalProvider = Provider<AgentWebApproval>((ref) {
  final gate = AgentWebApproval(
    changed: (questions) {
      ref.read(agentWebQuestionsProvider.notifier).state = questions;
    },
  );
  ref.onDispose(gate.dispose);
  return gate;
});
