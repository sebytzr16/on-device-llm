part of 'chat_provider.dart';

mixin _ChatWorkspace on _ChatBase {
  /// Deletes a project with the knowledge collection it owns. The project's
  /// chats stay; the collection's documents, originals and vectors go only
  /// when no other project or setting still uses that collection (S13/S14).
  Future<void> deleteProject(String id) async {
    final workspace = ref.read(conversationWorkspaceProvider);
    final project = workspace.projects.where((p) => p.id == id).firstOrNull;
    await ref.read(conversationWorkspaceProvider.notifier).removeProject(id);
    final collection = project?.collection.trim() ?? '';
    if (collection.isEmpty) return;
    await ref.read(settingsProvider.notifier).ready;
    await ref.read(presetsProvider.notifier).ready;
    await ref.read(modelProfilesProvider.notifier).ready;
    final db = ref.read(appDatabaseProvider);
    // Every layer that can name the collection, decoded and sanitized the
    // way the resolver reads it: a chat, a preset or a model profile that
    // still resolves to it keeps the documents alive (review 2026-11-20).
    bool names(Map<String, dynamic> overrides) =>
        overrides['knowledgeCollection'] == collection;
    final usedElsewhere =
        workspace.projects.any(
          (p) => p.id != id && p.collection.trim() == collection,
        ) ||
        ref.read(settingsProvider).knowledgeCollection == collection ||
        ref
            .read(presetsProvider)
            .presets
            .any((p) => names(SettingsResolver.sanitize(p.toOverrides()))) ||
        ref
            .read(modelProfilesProvider)
            .values
            .any((p) => names(SettingsResolver.sanitize(p))) ||
        // Decoded, not a substring: a chat keeps other override keys next to
        // `knowledgeCollection`, so the encoded form is not a stable needle.
        (await db.select(db.chats).get()).any(
          (c) => names(ChatNotifier.overridesOf(c)),
        );
    if (usedElsewhere) return;
    await DeletionCleanup.deleteKnowledgeCollection(db, collection);
  }

  Future<
    ({String system, String notes, String researchNotes, List<String> facts})
  >
  _baseSystem(
    String input, {
    required InferenceSettings settings,
    required Preset preset,
    String? extraSystem,
    bool? spoken,
  });
  Future<void> _startAnswer(_Turn t, _Prompt prompt);
  Future<void> _runServerWorkspace(
    _Turn t,
    _Asked asked,
    WorkspaceClient client,
  ) async {
    t.serverWorkspace = true;
    final settings = t.settings!;
    final system = await _baseSystem(
      t.input,
      settings: settings,
      preset: asked.preset,
      extraSystem: t.extraSystem,
      spoken: t.spoken,
    );
    t.memoryFacts = system.facts;
    final messages = <Map<String, Object>>[
      {'role': 'system', 'content': '${system.system}\n${system.notes}'},
    ];
    final live = state.messages
        .where(
          (m) =>
              ChatNotifier.isLive(m) &&
              m.id != t.assistantId &&
              m.id != asked.user.id,
        )
        .toList();
    final history = [...live, asked.user];
    // Use complete recent messages. The server owns all attachment extraction,
    // retrieval, model/tool rounds and helper execution.
    final recent = history.length > 30
        ? history.sublist(history.length - 30)
        : history;
    for (final message in recent) {
      messages.add({'role': message.role.name, 'content': message.content});
    }
    final prompt = (
      messages: messages,
      tools: <ToolSpec>[],
      nativeTools: false,
      researchTurn: false,
      sum: null,
    );
    await _startAnswer(t, prompt);
    state = state.copyWith(notice: _t.workspaceWorking);
    final requestId = t.assistantId;
    Future<List<Map<String, Object>>> prepareUploads() async {
      final uploads = <Map<String, Object>>[];
      for (var index = 0; index < recent.length; index++) {
        for (final attachment in recent[index].attachments) {
          if (attachment.isImage
              ? !settings.remoteVision
              : !settings.remoteDocuments) {
            continue;
          }
          // Stop during the upload phase: hand back what was prepared. The
          // cancelled token aborts the job POST, so run() exits quietly and
          // the turn is recorded as stopped, not failed.
          if (_cancelled) return uploads;
          state = state.copyWith(
            notice: _t.workspaceUploading(attachment.name),
          );
          final id = await client.upload(
            settings,
            attachment.path,
            attachment.name,
            batch: requestId,
            cancel: _retrievalCancel,
          );
          uploads.add({'uploadId': id, 'message': index + 1});
        }
      }
      return uploads;
    }

    String? failure;
    try {
      await client.run(
        settings: settings,
        requestId: requestId,
        messages: messages,
        prepareUploads: prepareUploads,
        cancel: _retrievalCancel,
        webOnly: !t.userTools,
        phoneActions: !DesktopHost.active && settings.toolActions,
        approve: (description, approvalId) async {
          if (description.startsWith('MCP:')) {
            return ref
                .read(agentWebApprovalProvider)
                .request(
                  chatId: '${t.chatId}:workspace:$approvalId',
                  mode: AgentWebAccess.askOnce,
                  description: description,
                  read: () async => null,
                  save: (_) async {},
                  cancel: _retrievalCancel,
                );
          }
          final decisions = AgentWebDecisions(t.db);
          return ref
              .read(agentWebApprovalProvider)
              .request(
                chatId: t.chatId!,
                mode: settings.agentWebAccess,
                read: () => decisions.read(t.chatId!),
                save: (allow) => decisions.write(t.chatId!, allow),
                cancel: _retrievalCancel,
              );
        },
        event: (event) {
          if (!_alive || _cancelled) return;
          final data = Map<String, dynamic>.from(
            (event['data'] as Map?) ?? const {},
          );
          switch (event['type']) {
            case 'reconnecting':
              state = state.copyWith(notice: _t.workspaceReconnecting);
            case 'queued':
              state = state.copyWith(notice: _t.workspaceQueued);
            case 'started':
              state = state.copyWith(notice: _t.workspaceWorking);
            case 'round':
              t.parser?.close();
              unawaited(t.answerSub?.cancel());
              unawaited(t.thinkSub?.cancel());
              t.clearAnswer();
              t.newParser();
            case 'activity_text':
              t.parser?.add(data['text'] as String);
            case 'answer':
              t.parser?.close();
              t.replaceAnswer(data['text'] as String);
            case 'tool_started':
              final name = data['name'] as String;
              state = state.copyWith(notice: _t.workspaceTool(name));
              t.thinking.write('\n▸ Server: $name\n');
            case 'tool_finished':
              if (data['result'] is Map) {
                t.serverToolTrace.add(
                  Map<String, dynamic>.from(data['result'] as Map),
                );
              }
              t.thinking.write(
                '\n▸ ${data['name']}: ${data['ok'] == true ? 'done' : 'failed'}\n',
              );
            case 'attachment_started':
            case 'attachment_progress':
              state = state.copyWith(
                notice: _t.workspaceReading(
                  '${data['name']}',
                  data['page'] == null
                      ? ''
                      : ' (${data['page']}/${data['total']})',
                ),
              );
            case 'attachment_finished':
              state = state.copyWith(notice: _t.workspaceWorking);
            case 'sources':
              t.sources = SearchSteps.sourcesFromJson(
                jsonEncode(data['items']),
              );
            case 'metrics':
              t.metrics = data;
              if (t.engine is RemoteEngine) {
                (t.engine as RemoteEngine).metrics = data;
              }
              state = state.copyWith(metrics: {...data, 'execution': 'server'});
            case 'agent':
              final phase =
                  HelperPhase.values
                      .where((p) => p.name == data['phase'])
                      .firstOrNull ??
                  HelperPhase.failed;
              final duration = Duration(
                milliseconds: data['elapsedMs'] as int? ?? 0,
              );
              ref
                  .read(helperJobsProvider.notifier)
                  .publish(
                    HelperJob(
                      id: '${event['jobId']}:${data['id']}',
                      task: data['task'] as String,
                      inputPreview: '',
                      modelName: '${data['modelName']} · ${_t.workspaceServer}',
                      messageId: t.assistantId,
                      phase: phase,
                      output: data['output'] as String? ?? '',
                      thinking: data['thinking'] as String? ?? '',
                      elapsed: duration,
                      firstToken: data['firstTokenMs'] is int
                          ? Duration(milliseconds: data['firstTokenMs'] as int)
                          : null,
                      metrics: Map<String, dynamic>.from(
                        (data['metrics'] as Map?) ?? const {},
                      ),
                      reason: data['reason'] as String?,
                      reply: phase == HelperPhase.done
                          ? HelperReply(
                              text: data['output'] as String,
                              took: duration,
                              modelName:
                                  '${data['modelName']} · ${_t.workspaceServer}',
                            )
                          : null,
                    ),
                  );
            case 'failed':
              failure =
                  data['message'] as String? ?? 'Server execution failed.';
            case 'cancelled':
              failure =
                  data['reason'] as String? ?? 'The server stopped this task.';
            case 'done':
              state = state.copyWith(clearNotice: true);
          }
        },
      );
    } catch (error) {
      failure ??= '$error';
      rethrow;
    } finally {
      if (_cancelled || failure != null) {
        final jobs = ref
            .read(helperJobsProvider)
            .jobs
            .where((job) => job.messageId == t.assistantId && !job.terminal)
            .toList();
        for (final job in jobs) {
          ref
              .read(helperJobsProvider.notifier)
              .publish(
                job.ended(
                  _cancelled ? HelperPhase.cancelled : HelperPhase.failed,
                  failure ?? 'Stopped by the user.',
                ),
              );
        }
      }
    }
    if (failure != null) throw StateError(failure!);
  }
}
