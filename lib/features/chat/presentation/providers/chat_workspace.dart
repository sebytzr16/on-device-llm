part of 'chat_provider.dart';

mixin _ChatWorkspace on _ChatBase {
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
    final uploads = <Map<String, Object>>[];
    if (!await client.hasRetainedJob(settings, requestId)) {
      for (var index = 0; index < recent.length; index++) {
        for (final attachment in recent[index].attachments) {
          if (attachment.isImage
              ? !settings.remoteVision
              : !settings.remoteDocuments) {
            continue;
          }
          if (_cancelled) return;
          state = state.copyWith(
            notice: _t.workspaceUploading(attachment.name),
          );
          final id = await client.upload(
            settings,
            attachment.path,
            attachment.name,
            cancel: _retrievalCancel,
          );
          uploads.add({'uploadId': id, 'message': index + 1});
        }
      }
    }
    String? failure;
    try {
      await client.run(
        settings: settings,
        requestId: requestId,
        messages: messages,
        uploads: uploads,
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
