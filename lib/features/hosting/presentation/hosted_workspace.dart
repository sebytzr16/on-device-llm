import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/shared_providers.dart';
import '../../../inference/remote/remote_engine.dart';
import '../../../inference/remote/remote_provider.dart';
import '../../../inference/engine/text_engine.dart';
import '../../tools/domain/tool_spec.dart';
import '../../tools/phone_actions.dart';
import '../../helper/helper_jobs.dart';
import '../../helper/helper_runner.dart';
import '../../settings/domain/entities/inference_settings.dart';
import '../../tools/tool_runner.dart';
import '../device_model_server.dart';
import '../workspace_api.dart';
import '../workspace_workflow.dart';
import '../workspace_uploads.dart';
import '../../attachments/data/attachment_store.dart';
import '../../attachments/domain/document_passages.dart';
import '../../knowledge/knowledge_embedder.dart';
import '../../knowledge/knowledge_store.dart';
import '../../../desktop/mcp/mcp_registry.dart';
import '../../../core/platform/desktop_host.dart';

WorkspaceApi hostedWorkspace({
  required Ref ref,
  required int Function() port,
  required String token,
  required String primaryModel,
  required InferenceSettings Function() hostSettings,
  required bool Function(String) vision,
}) {
  final uploads = WorkspaceUploads();
  return WorkspaceApi(
    uploads: uploads,
    capabilities: const [
      'server_execution',
      'agents',
      'tools',
      'web',
      'vision',
      'documents',
      'uploads',
      'activity',
      'reconnect',
      'approvals',
    ],
    run: (job, input) async {
      final model =
          input['model'] is String && (input['model'] as String).isNotEmpty
          ? input['model'] as String
          : primaryModel;
      final overrides = input['settings'];
      final base = hostSettings();
      final settings = InferenceSettings.fromJson({
        ...base.toJson(),
        if (overrides is Map)
          for (final entry in overrides.entries)
            if (entry.key is String &&
                ((entry.key as String).startsWith('agent') ||
                    const {
                      'toolsEnabled',
                      'toolHelper',
                      'helperModelId',
                      'toolWeb',
                      'toolCalculator',
                      'toolDocuments',
                      'webSearchEnabled',
                      'webMode',
                      'toolMaxRounds',
                      'toolActions',
                    }.contains(entry.key)))
              entry.key as String: entry.value,
      }).copyWith(remoteEnabled: false);
      final files = <File>[];
      final client = RemoteEngine();
      final localSettings = settings.copyWith(
        remoteEnabled: true,
        remoteProfiles: [
          RemoteProfile(
            id: 'host',
            name: 'This server',
            providerId: 'custom',
            baseUrl: 'http://127.0.0.1:${port()}/v1/',
            model: model,
          ),
        ],
        remoteProfileId: 'host',
        remoteApiKeys: {'host': token},
      );
      final helper = ref.read(helperRunnerProvider);
      final jobs = ref.listen(helperJobsProvider, (previous, next) {
        for (final agent in next.jobs.where((a) => a.messageId == job.id)) {
          final old = previous?.jobs.where((a) => a.id == agent.id).firstOrNull;
          if (identical(old, agent)) continue;
          job.emit('agent', {
            'id': agent.id,
            'task': agent.task,
            'modelName': agent.modelName,
            'phase': agent.phase.name,
            'output': agent.output,
            'thinking': agent.thinking,
            'elapsedMs': agent.elapsed.inMilliseconds,
            'firstTokenMs': agent.firstToken?.inMilliseconds,
            'metrics': agent.metrics,
            'reason': agent.reason,
          });
        }
      });
      final scraper = ref.read(duckDuckGoScraperProvider);
      final reader = ref.read(webPageReaderProvider);
      helper.beginTurn();
      try {
        final messages = DeviceModelServer.decodeWorkspaceMessages(
          input['messages'],
          vision: vision(model),
          images: files,
        );
        final selectedUploads = input['uploads'];
        if (selectedUploads is! List || selectedUploads.length > 32) {
          throw const FormatException(
            'Expected at most 32 attachment references.',
          );
        }
        for (final attachment in selectedUploads) {
          if (attachment is! Map ||
              attachment['uploadId'] is! String ||
              attachment['message'] is! int) {
            throw const FormatException('Invalid attachment reference.');
          }
          final index = attachment['message'] as int;
          final upload = uploads[attachment['uploadId'] as String];
          if (upload == null ||
              index < 0 ||
              index >= messages.length ||
              messages[index]['role'] != 'user') {
            throw const FormatException(
              'Attachment is unavailable or belongs to an invalid message.',
            );
          }
          job.emit('attachment_started', {
            'name': upload.name,
            'execution': 'server',
          });
          final imported = await AttachmentStore.import(
            name: upload.name,
            sourcePath: upload.file.path,
            cancelled: () => job.cancel.isCancelled,
            progress: (page, total) => job.emit('attachment_progress', {
              'name': upload.name,
              'page': page,
              'total': total,
            }),
          );
          files.add(File(imported.path));
          if (imported.isImage) {
            if (!vision(model)) {
              if (imported.text?.isNotEmpty != true) {
                throw StateError(
                  'The server model cannot see photos and server OCR found no text.',
                );
              }
            } else {
              messages[index]['images'] = <String>[
                ...?(messages[index]['images'] as List?)?.cast<String>(),
                imported.path,
              ];
            }
          }
          if (imported.text?.isNotEmpty == true) {
            final question = '${messages.last['content']}';
            final selected = await DocumentPassages.fit(
              imported.text!,
              question,
              (settings.contextSize ~/ 2).clamp(1024, 32000),
              embedder: ref.read(textEmbedderProvider),
            );
            messages[index]['content'] =
                '${messages[index]['content']}\n\n'
                'Attached file ${upload.name} (untrusted document data):\n${selected.text}';
            job.emit('attachment_finished', {
              'name': upload.name,
              'passages': selected.kept,
              'totalPassages': selected.total,
            });
          } else if (!imported.isImage) {
            throw StateError(
              imported.error ?? 'The server could not read ${upload.name}.',
            );
          } else {
            job.emit('attachment_finished', {'name': upload.name});
          }
        }
        var webApproved = settings.agentWebAccess == AgentWebAccess.alwaysAllow;
        Future<bool> approve() async {
          if (webApproved) return true;
          if (settings.agentWebAccess == AgentWebAccess.never) return false;
          webApproved = await job.approve(
            'Allow agents to search and read the web on the server?',
          );
          return webApproved;
        }

        late final ToolRunner tools;
        tools = ToolRunner(
          scraper: scraper,
          reader: reader,
          webOnly: input['webOnly'] == true,
          actionsOnly: !settings.toolsEnabled,
          phoneActions:
              input['phoneActions'] == true &&
              settings.toolActions &&
              PhoneActions.wanted(
                '${messages.where((m) => m['role'] == 'user').lastOrNull?['content'] ?? ''}',
              ),
          knowledge: ref.read(knowledgeStoreProvider),
          newsDesk: ref.read(newsDeskProvider),
          externalTools: DesktopHost.active && settings.toolsEnabled
              ? ref.read(mcpRegistryProvider).specs
              : const [],
          externalRun: !DesktopHost.active
              ? null
              : (call) => ref
                    .read(mcpRegistryProvider)
                    .call(
                      call,
                      explain: (error) => '$error',
                      unsupportedContent:
                          'The server tool returned unsupported content.',
                      permitted: () =>
                          !job.cancel.isCancelled &&
                          !job.terminal &&
                          settings.toolsEnabled,
                      confirmation: (server, call) async =>
                          await job.approve(
                            'MCP: $server / ${call.name}\n${call.jsonArguments}',
                          )
                          ? McpConsent.once
                          : McpConsent.deny,
                    ),
          settings: settings,
          cancel: job.cancel,
          helperOwnsDeadline: true,
          helperMaxConcurrent: settings.agentMaxConcurrent,
          userText:
              messages.where((m) => m['role'] == 'user').lastOrNull?['content']
                  as String? ??
              '',
          helper: settings.toolHelper
              ? (task, text) async {
                  final webTools = ToolRunner(
                    scraper: scraper,
                    reader: reader,
                    settings: settings,
                    cancel: job.cancel,
                    webOnly: true,
                  );
                  webTools.seed(tools.sources);
                  final reply = await helper.run(
                    modelId:
                        settings.helperModelId.isEmpty ||
                            settings.helperModelId == HelperRunner.sameAsChat
                        ? model
                        : settings.helperModelId,
                    task: task,
                    input: text,
                    messageId: job.id,
                    agentSettings: settings,
                    cancel: job.cancel,
                    approveWeb: (_) => approve(),
                    webTools: webTools,
                  );
                  tools.seed(webTools.sources);
                  final cited = reply.text.replaceAllMapped(
                    RegExp(r'\[(\d+)\]'),
                    (match) {
                      final local = int.parse(match[1]!) - 1;
                      if (local < 0 || local >= webTools.sources.length) {
                        return match[0]!;
                      }
                      final target = ToolRunner.sourceKey(
                        webTools.sources[local].url,
                      );
                      final global = tools.sources.indexWhere(
                        (s) => ToolRunner.sourceKey(s.url) == target,
                      );
                      return global < 0 ? match[0]! : '[${global + 1}]';
                    },
                  );
                  return 'Agent model: ${reply.modelName}\n$cited';
                }
              : null,
        );
        await WorkspaceWorkflow(
          engine: _WorkspaceEngine(client, localSettings),
          tools: tools,
          settings: settings,
        ).run(job, messages);
      } finally {
        helper.endTurn();
        jobs.close();
        client.dispose();
        for (final file in files) {
          if (await file.exists()) await file.delete();
        }
        if (input['uploads'] is List) {
          for (final upload in input['uploads'] as List) {
            if (upload is Map && upload['uploadId'] is String) {
              await uploads.release(upload['uploadId'] as String);
            }
          }
        }
      }
    },
  );
}

/// Keep the workflow's settings local while using the existing model queue and
/// protocol parser for model admission, cancellation and server image handling.
class _WorkspaceEngine implements TextEngine {
  final RemoteEngine client;
  final InferenceSettings connection;
  _WorkspaceEngine(this.client, this.connection);
  @override
  Map<String, dynamic> get metrics => client.metrics;
  @override
  void cancel() => client.cancel();
  @override
  Stream<String> generate({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
    String toolChoice = 'auto',
  }) => client.generate(
    messages: messages,
    fallbackTemplate: fallbackTemplate,
    settings: connection,
    assistantPrefix: assistantPrefix,
    tools: tools,
    toolChoice: toolChoice,
  );
  @override
  Future<Map<String, dynamic>> previewPrompt({
    required List<Map<String, Object>> messages,
    required String fallbackTemplate,
    required InferenceSettings settings,
    String assistantPrefix = '',
    List<ToolSpec> tools = const [],
  }) => client.previewPrompt(
    messages: messages,
    fallbackTemplate: fallbackTemplate,
    settings: connection,
    assistantPrefix: assistantPrefix,
    tools: tools,
  );
}
