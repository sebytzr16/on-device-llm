import 'dart:async';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'dart:math';
import 'dart:io' show Platform, Directory;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../../../tools/project_file_tools.dart';
import '../../../tools/file_approval.dart';
import '../../../attachments/domain/document_passages.dart';
import '../../../../desktop/chat_image_generation.dart';
import '../../../../desktop/mcp/mcp_registry.dart';
import '../../../../desktop/mcp/mcp_strings.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/platform/build_identity.dart';
import '../../../../core/l10n/l10n.dart';
import '../../../../core/providers/shared_providers.dart';
import '../../../../data/network/web_search/instant_answers.dart';
import '../../../../data/local/database/app_database.dart';
import '../../../../data/network/web_search/duckduckgo_scraper.dart';
import '../../../../data/network/web_search/search_models.dart';
import '../../../../data/network/web_search/web_page_reader.dart';
import '../../../../data/network/web_search/wikipedia_client.dart';
import '../../../../inference/engine/stream_parser.dart';
import '../../../attachments/domain/attachment.dart';
import '../../../knowledge/knowledge_embedder.dart';
import '../../../knowledge/knowledge_store.dart';
import '../../../retrieval/claim_check_runner.dart';
import '../../../retrieval/domain/claim_check.dart';
import '../../../retrieval/domain/date_check.dart';
import '../../../retrieval/semantic_rerank.dart';
import '../../../retrieval/overlap_prefill.dart';
import '../../../../inference/engine/llama_engine.dart';
import '../../../retrieval/support_check.dart';
import '../../../memory/domain/user_memory.dart';
import '../../domain/message_deletion.dart';
import '../../domain/deletion_cleanup.dart';
import '../../domain/tool_result_cut.dart';
import '../../domain/chat_copy_repository.dart';
import '../../domain/conversation_workspace.dart';
import '../../domain/temporary_files.dart';
import '../../domain/context_summary.dart';
import '../../domain/turn_coordinator.dart';
import '../../../memory/presentation/providers/memory_provider.dart';
import '../../../../inference/engine/text_engine.dart';
import '../../../../inference/engine/diffusiongemma_engine.dart';
import '../../../../inference/engine/turn_budget.dart';
import '../../../../inference/remote/remote_engine.dart';
import '../../../retrieval/domain/citation_match.dart';
import '../../../retrieval/domain/evidence_audit.dart';
import '../../../models/domain/entities/model_info.dart';
import '../../../presets/domain/preset.dart';
import '../../../presets/presentation/providers/presets_provider.dart';
import '../../../models/presentation/providers/model_manager_provider.dart';
import '../../../models/presentation/providers/model_recommendations_provider.dart';
import '../../../adapters/adapter_store.dart';
import '../../../settings/domain/entities/inference_settings.dart';
import '../../../settings/domain/settings_scope.dart';
import '../../../../core/platform/desktop_host.dart';
import '../../../../core/platform/device_info.dart';
import '../../../hosting/presentation/device_hosting_provider.dart';
import '../../../settings/domain/battery_saver.dart';
import 'chat_model_pins.dart';
import 'search_misses.dart';
import '../../../settings/presentation/providers/effective_settings_provider.dart';
import '../../../settings/presentation/providers/model_profiles_provider.dart';
import '../../../settings/presentation/providers/settings_provider.dart';
import '../../../tools/domain/tool_markup.dart';
import '../../../tools/domain/tool_spec.dart';
import '../../../tools/tool_runner.dart';
import '../../../helper/helper_runner.dart';
import '../../../../inference/remote/workspace_client.dart';
import '../../../helper/helper_request.dart';
import '../../../helper/helper_jobs.dart';
import '../../../helper/helper_web_approval.dart';
import '../../../tools/phone_actions.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/export/chat_document.dart';
import '../../domain/entities/turn_run.dart';
import '../../domain/entities/reasoning_block.dart';
import '../../domain/answer_cleanup.dart';
import '../../domain/answer_shape.dart';
import '../../domain/retrieval_plan.dart';
import '../../domain/source_dates.dart';
import '../../domain/research_recipes.dart';
import '../../domain/context_use.dart';
import '../../domain/about_user.dart';
import '../../domain/math_question.dart';
import '../../../retrieval/domain/evidence.dart';
import '../../../retrieval/domain/life_dates.dart';
import '../../../retrieval/domain/news_intent.dart';
import '../../../retrieval/domain/source_quality.dart';
import '../../../retrieval/domain/primary_discovery.dart';
import '../../../retrieval/domain/wikipedia_sources.dart';
import '../../../retrieval/domain/subject_terms.dart';
import '../../domain/turn_prompts.dart';
import '../../domain/turn_policy.dart';
import '../../domain/answer_checks.dart';
import '../../domain/search_steps.dart';
import '../../domain/chat_titles.dart';
import 'package:ondevice_llm/core/logging/quiet_failure.dart';

part 'chat_send.dart';
part 'chat_preparation.dart';
part 'chat_retrieval.dart';
part 'chat_prompt.dart';
part 'chat_streaming.dart';
part 'chat_rounds.dart';
part 'chat_completion.dart';
part 'chat_titles.dart';
part 'chat_tools.dart';
part 'chat_attachments.dart';
part 'chat_web_evidence.dart';
part 'chat_web_sources.dart';
part 'chat_web.dart';
part 'chat_branches.dart';
part 'chat_memory.dart';
part 'chat_export.dart';
part 'chat_turn.dart';
part 'chat_prime.dart';
part 'chat_workspace.dart';

final _turnLog = Logger('chat');

class ChatState {
  final List<ChatMessage> messages;
  final bool isGenerating, isLoadingModel;
  final bool hasReasoningTokens;
  final ReasoningBlock? reasoning;
  final String partialAnswer;
  final String? error, chatId, notice;
  final Map<String, dynamic> metrics;
  final bool temporary;

  /// The turn's answer is saved into [messages] while the turn still runs
  /// (memory, the chat's title): the live bubble hides, or the answer
  /// showed twice while the chat was named.
  final bool answerSaved;

  /// Whether the list shows the answer being written below [messages].
  bool get showsLiveAnswer => isGenerating && !answerSaved;

  /// Facts the memory feature just stored from the last message, for the
  /// compact banner with its edit/discard affordance.
  final List<Memory> learned;
  const ChatState({
    this.messages = const [],
    this.isGenerating = false,
    this.isLoadingModel = false,
    this.hasReasoningTokens = false,
    this.reasoning,
    this.partialAnswer = '',
    this.error,
    this.chatId,
    this.notice,
    this.metrics = const {},
    this.learned = const [],
    this.temporary = false,
    this.answerSaved = false,
  });
  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isGenerating,
    bool? isLoadingModel,
    bool? hasReasoningTokens,
    ReasoningBlock? reasoning,
    bool clearReasoning = false,
    String? partialAnswer,
    String? error,
    bool clearError = false,
    String? chatId,
    String? notice,
    bool clearNotice = false,
    Map<String, dynamic>? metrics,
    List<Memory>? learned,
    bool? answerSaved,
  }) => ChatState(
    messages: messages ?? this.messages,
    isGenerating: isGenerating ?? this.isGenerating,
    isLoadingModel: isLoadingModel ?? this.isLoadingModel,
    hasReasoningTokens: hasReasoningTokens ?? this.hasReasoningTokens,
    reasoning: clearReasoning ? null : reasoning ?? this.reasoning,
    partialAnswer: partialAnswer ?? this.partialAnswer,
    error: clearError ? null : error ?? this.error,
    chatId: chatId ?? this.chatId,
    notice: clearNotice ? null : notice ?? this.notice,
    metrics: metrics ?? this.metrics,
    learned: learned ?? this.learned,
    answerSaved: answerSaved ?? this.answerSaved,
    temporary: temporary,
  );
}

final chatsProvider = StreamProvider<List<Chat>>(
  (ref) => ref.watch(appDatabaseProvider).watchAllChats(),
);

/// State shared by [ChatNotifier] and its parts (web retrieval, branches,
/// memory, export), plus the members the parts call on the notifier.
abstract class _ChatBase extends Notifier<ChatState> {
  AppDatabase? _temporaryDb;
  Future<void> _temporaryReady = Future.value();
  String? _projectId;
  AppDatabase get _database => _temporaryDb ?? ref.read(appDatabaseProvider);
  final _turns = TurnCoordinator();

  /// Who sent the running turn ([ChatNotifier.send]'s `owner`).
  Object? _turnOwner;
  bool get _cancelled => _turns.active?.cancelled ?? false;

  /// The current turn is heard, not read ([send]'s `spoken`).
  bool _spoken = false;

  /// A spoken first exchange's chat title, written by [nameChatLater] once
  /// the voice is quiet: written during the turn it held the end of the
  /// answer back and slowed the voice reading it (phone, 2026-10-07).
  Future<void> Function(bool Function() keep)? _titleLater;

  /// A spoken turn's memory update, run by [nameChatLater] before the
  /// title: run during the answer it competed with the voice for the CPU
  /// (audit E1, 2026-10-08).
  Future<void> Function(bool Function() keep)? _memoryLater;
  Future<void>? _naming;
  var _namingStopped = false;
  bool _alive = true;
  int _navigation = 0;
  int _fittedOmitted = 0;
  CancelToken? get _retrievalCancel => _turns.active?.retrieval;

  /// Notices and errors in the app's language (Settings > Language).
  AppLocalizations get _t => stringsFor(ref.read(settingsProvider).localeCode);

  ChatMessage? get _lastLiveUser;
  ChatMessage? get _lastLiveAssistant;
  ChatMessage _fromRow(Message row);
  Future<void> _supersede(ChatMessage m);
  Future<bool> send(
    String input, {
    bool insertUser = true,
    ChatMessage? resume,
    List<Attachment> attachments = const [],
    // Conversation with a model that hears: the utterance's recording, used
    // in this turn's prompt only (never saved with the chat).
    String? audioPath,
    ModelInfo? compareWith,
    String? reuseSourcesJson,
    String? parentId,
    Map<String, dynamic> turnOverrides = const {},
    String? extraSystem,
    bool forceResearch = false,
    bool isolated = false,
    String? promptOverride,
    List<SearchResult>? answerSources,
    bool learn = true,
    SubjectTerms? subject,
    String subjectAllowed = '',
    bool localOnly = false,
    bool spoken = false,
  });
}

class ChatNotifier extends _ChatBase
    with _ChatBranches, _ChatMemory, _ChatExport, _ChatWorkspace {
  // Riverpod remains the composition and lifecycle boundary for the parts.
  Ref get _chatRef => ref;
  ChatState get _chatState => state;
  set _chatState(ChatState value) => state = value;

  int _primeEpoch = 0, _primedLoad = -1;

  /// Called only for completed loads on the chat's local engine.
  Future<void> primeLoadedModel(ModelInfo model) => _primeLoadedModel(model);

  /// How often a streaming answer is pushed to the screen (about 30 a
  /// second, so the per-word fade reads smoothly).
  static const repaintInterval = Duration(milliseconds: 33);

  /// How often partial output is written to the database while streaming
  /// (CHAT-01). Bounds the loss on an abrupt kill; tests shorten it.
  static Duration checkpointInterval = const Duration(seconds: 1);

  // Recent (time, tok/s) samples for the throttling advisory (North Star §12).
  final _rates = <(DateTime, double)>[];

  /// Chats that were offered tools in this run: they keep them, so the
  /// prompt's prefix (tool descriptions come first) stays the same from
  /// turn to turn and the engine reuses its cache.
  final _toolChats = <String>{};

  /// Chats that were offered the phone actions: with the other tools off,
  /// they keep those, for the same reason (phone, 2026-10-08: the turn
  /// after a timer read 1412 tokens again, 16 s before its first word).
  final _actionChats = <String>{};

  /// A sustained drop of more than 40 % against the best recent rate usually
  /// means thermal throttling. Say so instead of letting the phone crawl.
  String? _throttleNotice(Map<String, dynamic> m) {
    final rate = (m['tokensPerSecond'] as num?)?.toDouble() ?? 0;
    final tokens = m['tokens'] as int? ?? 0;
    if (rate <= 0 || tokens < 32) return null;
    final now = DateTime.now();
    _rates.removeWhere(
      (r) => now.difference(r.$1) > const Duration(minutes: 2),
    );
    final best = _rates.fold(0.0, (b, r) => r.$2 > b ? r.$2 : b);
    _rates.add((now, rate));
    if (best > 0 && rate < best * 0.6) {
      final drop = ((1 - rate / best) * 100).round();
      return _t.noticeThrottle(
        drop,
        best.toStringAsFixed(1),
        rate.toStringAsFixed(1),
      );
    }
    return null;
  }

  @override
  ChatState build() {
    final engine = ref.read(llamaEngineProvider);
    final remote = ref.read(remoteEngineProvider);
    final diffusion = ref.read(diffusionGemmaEngineProvider);
    ref.onDispose(() {
      _alive = false;
      _turns.dispose();
      engine.cancel();
      remote.cancel();
      diffusion.cancel();
      unawaited(_temporaryDb?.close());
    });
    _temporaryReady = TemporaryFiles.clear().catchError((Object _) {});
    return const ChatState();
  }

  void newChat({bool temporary = false, String? projectId}) {
    if (state.isGenerating) return;
    if (_temporaryDb != null) {
      unawaited(_temporaryDb!.close());
      _temporaryReady = TemporaryFiles.clear().catchError((Object _) {});
    }
    _temporaryDb = temporary
        ? AppDatabase.forTesting(NativeDatabase.memory())
        : null;
    _projectId = projectId;
    ref.read(newChatProjectProvider.notifier).state = projectId;
    _navigation++;
    state = ChatState(temporary: temporary);
    ref.read(chatOverridesProvider.notifier).state = const {};
  }

  /// Chat-level setting overrides (roadmap P1.4): kept in memory for a chat
  /// that has no row yet, written to `chats.overrides_json` otherwise.
  Future<void> setChatOverrides(Map<String, dynamic> overrides) async {
    final clean = SettingsResolver.sanitize(overrides);
    ref.read(chatOverridesProvider.notifier).state = clean;
    final id = state.chatId;
    if (id == null) return;
    final db = _database;
    await db.transaction(() async {
      final previous = AgentWebDecisions.decode(
        (await db.getChat(id))?.overridesJson ?? '{}',
      );
      await (db.update(db.chats)..where((t) => t.id.equals(id))).write(
        ChatsCompanion(
          overridesJson: drift.Value(
            jsonEncode({
              ...clean,
              for (final entry in previous.entries)
                if (entry.key.startsWith('_fileEditsAllowed:') &&
                    entry.value is bool)
                  entry.key: entry.value,
              if (previous[agentWebDecisionKey] is bool)
                agentWebDecisionKey: previous[agentWebDecisionKey],
            }),
          ),
        ),
      );
    });
  }

  static Map<String, dynamic> overridesOf(Chat? chat) {
    if (chat == null) return const {};
    try {
      final j = jsonDecode(chat.overridesJson);
      return j is Map
          ? SettingsResolver.sanitize(Map<String, dynamic>.from(j))
          : const {};
    } catch (_) {
      return const {};
    }
  }

  /// Duplicate or branch a persistent chat, then open the independent copy.
  Future<String?> copyChat(String id, {String? throughMessageId}) async {
    if (state.isGenerating || ref.read(sessionBusyProvider)) {
      return null;
    }
    final revision = _navigation;
    final db = ref.read(appDatabaseProvider);
    state = state.copyWith(isGenerating: true, clearError: true);
    String? copied;
    try {
      final chat = await db.getChat(id);
      if (chat == null) return null;
      final title = chat.title.length > 180
          ? chat.title.substring(0, 180)
          : chat.title;
      copied = await ChatCopyRepository(db).copy(
        id,
        throughMessageId: throughMessageId,
        title: throughMessageId == null
            ? _t.desktopChatCopyTitle(title)
            : _t.desktopChatBranchTitle(title),
      );
    } catch (_) {
      if (_alive) state = state.copyWith(error: _t.desktopChatActionFailed);
    } finally {
      if (_alive) state = state.copyWith(isGenerating: false);
    }
    if (copied != null && _alive && revision == _navigation) {
      await openChat(copied);
    }
    return copied;
  }

  Future<void> openChat(String id) async {
    if (state.isGenerating) return;
    if (_temporaryDb != null) newChat();
    await ref.read(conversationWorkspaceProvider.notifier).ready;
    _projectId = ref.read(conversationWorkspaceProvider).memberships[id];
    final revision = ++_navigation;
    try {
      final db = ref.read(appDatabaseProvider);
      var rows = await db.getMessages(id);
      if (rows.any(
        (r) =>
            (r.status == 'generating' || r.status == 'alternative:generating'),
      )) {
        await db.markInterruptedRuns();
        rows = await db.getMessages(id);
      }
      if (_alive && revision == _navigation) {
        state = ChatState(chatId: id, messages: rows.map(_fromRow).toList());
        ref.read(chatOverridesProvider.notifier).state = overridesOf(
          await db.getChat(id),
        );
      }
    } catch (e) {
      if (_alive) state = state.copyWith(error: 'Cannot open chat: $e');
    }
  }

  /// The downloaded model pinned to [chatId], if any.
  ModelInfo? pinnedModel(String? chatId) {
    if (chatId == null) return null;
    final id = ref.read(chatModelPinsProvider)[chatId];
    if (id == null) return null;
    return ref
        .read(modelManagerProvider)
        .catalog
        .where((m) => m.id == id && m.isDownloaded)
        .firstOrNull;
  }

  Future<void> deleteChat(String id) async {
    if (state.isGenerating) return;
    unawaited(ref.read(chatModelPinsProvider.notifier).set(id, null));
    // Files, drafts, generated revisions and vectors the chat owns go with it
    // where nothing else references them (S13/S14).
    await DeletionCleanup.deleteChat(ref.read(appDatabaseProvider), id);
    await ContextSummary.remove(id);
    await ref.read(conversationWorkspaceProvider.notifier).forget(id);
    if (state.chatId == id) newChat();
  }

  @override
  ChatMessage _fromRow(Message r) => ChatMessage(
    id: r.id,
    role: ChatRole.values.byName(r.role),
    content: r.content,
    reasoning: r.reasoning,
    timestamp: r.timestamp,
    tokenCount: r.tokenCount,
    status: r.status,
    sourcesJson: r.sourcesJson,
    modelId: r.modelId,
    attachments: Attachment.listFromJson(jsonDecode(r.attachmentsJson)),
    parentId: r.parentId,
    runJson: r.runJson,
  );

  /// Marks a turn superseded in the database and in the visible list. The
  /// record stays (roadmap CHAT-02: history is retained, never overwritten)
  /// but leaves the model context and collapses in the UI.
  @override
  Future<void> _supersede(ChatMessage m, {String? branch}) async {
    final status = 'superseded:${branch ?? const Uuid().v4()}:${m.status}';
    await _setStatus(m, status);
  }

  Future<void> _setStatus(ChatMessage m, String status) async {
    await _database.updateMessage(
      m.id,
      MessagesCompanion(status: drift.Value(status)),
    );
    state = state.copyWith(
      messages: [
        for (final x in state.messages)
          x.id == m.id ? x.copyWith(status: status) : x,
      ],
    );
  }

  /// Turns the model sees: not retained earlier versions, not comparison
  /// answers from another model.
  static bool isLive(ChatMessage m) => !m.isSuperseded && !m.isAlternative;

  @override
  ChatMessage? get _lastLiveUser => state.messages
      .where((m) => m.role == ChatRole.user && isLive(m))
      .lastOrNull;
  @override
  ChatMessage? get _lastLiveAssistant => state.messages
      .where((m) => m.role == ChatRole.assistant && isLive(m))
      .lastOrNull;

  /// [insertUser] false re-answers the existing last question; [resume]
  /// continues that assistant message from its saved text instead of
  /// starting a new one.
  ///
  /// A turn runs in named steps on one [_Turn]: [_prepareTurn] (settings,
  /// model, the saved question), [_planRetrieval], [_lookUp] (judge, web,
  /// Wikipedia), [_assemblePrompt], [_startAnswer], [_runRounds] (the
  /// model and its tools) and [_endTurn] (clean, check, save, learn).
  @override
  Future<bool> send(
    String input, {
    bool insertUser = true,
    ChatMessage? resume,
    List<Attachment> attachments = const [],
    // Conversation with a model that hears: the utterance's recording, used
    // in this turn's prompt only (never saved with the chat).
    String? audioPath,
    ModelInfo? compareWith,
    String? reuseSourcesJson,
    String? parentId,
    Map<String, dynamic> turnOverrides = const {},
    // Callers that drive the chat (Goals): [extraSystem] joins the system
    // prompt; [forceResearch] researches even when Auto would not (web
    // research must still be on); [isolated] sends this message without the
    // earlier turns; [promptOverride] replaces what the model is given for
    // this message (the visible message stays [input]) and
    // [answerSources] are stored as the answer's sources, with no retrieval.
    String? extraSystem,
    bool forceResearch = false,
    bool isolated = false,
    String? promptOverride,
    List<SearchResult>? answerSources,
    // False when [input] is not the user's own words about themself (a
    // prompt shortcut wrapped their text: "/translate My name is…" is text
    // to translate, not a fact to remember).
    bool learn = true,
    // Goals: the names the turn must stay on. Planned search queries are
    // repaired to them and pages about a neighbouring model are dropped
    // before and after reading ([SubjectTerms]); names in [subjectAllowed]
    // (the user's own words) are never treated as drift.
    SubjectTerms? subject,
    String subjectAllowed = '',
    TurnBudget? budget,
    // Conversation mode (tester, 2026-10-07): always the phone's own model,
    // even when a remote server is set up.
    bool localOnly = false,
    // Conversation: the answer is heard, so one from web pages is a few
    // spoken sentences instead of a list.
    bool spoken = false,
    // A Goal's step: the goal's Stop ends only its own turns.
    Object? owner,
  }) => _send(
    input,
    insertUser: insertUser,
    resume: resume,
    attachments: attachments,
    audioPath: audioPath,
    compareWith: compareWith,
    reuseSourcesJson: reuseSourcesJson,
    parentId: parentId,
    turnOverrides: turnOverrides,
    extraSystem: extraSystem,
    forceResearch: forceResearch,
    isolated: isolated,
    promptOverride: promptOverride,
    answerSources: answerSources,
    learn: learn,
    subject: subject,
    subjectAllowed: subjectAllowed,
    budget: budget,
    localOnly: localOnly,
    spoken: spoken,
    owner: owner,
  );

  /// CHAT-01: the assistant row exists before the first token, so a kill
  /// mid-answer leaves an interrupted message, not a missing one. Then the
  /// timers that save and paint the answer as it streams.
  @override
  Future<void> _startAnswer(_Turn t, _Prompt prompt) =>
      _startStreamingAnswer(t, prompt);

  /// The part of the system prompt every path of a turn shares: the app's
  /// default, the preset, the user's instructions and a caller's extra
  /// (Goals). Also the memory notes that follow it, [notes] for an ordinary
  /// turn and [researchNotes] for one that researches (pinned notes and how
  /// to answer only), and every note, for learning after the answer.
  @override
  Future<
    ({String system, String notes, String researchNotes, List<String> facts})
  >
  _baseSystem(
    String input, {
    required InferenceSettings settings,
    required Preset preset,
    String? extraSystem,
    bool? spoken,
  }) => _buildBaseSystem(
    input,
    settings: settings,
    preset: preset,
    extraSystem: extraSystem,
    spoken: spoken,
  );

  /// How long a chat waits for the device server to finish a request.
  static Duration hostedWait = const Duration(minutes: 3);

  /// Writes the title (and memory) a spoken turn left for later ([send]'s
  /// `spoken`), now that the answer has been heard. A new turn stops it; it is tried again
  /// on the next call.
  Future<void> nameChatLater() => _finishDeferredNaming();

  /// Stops the running turn only when [owner] sent it.
  void cancelOwned(Object owner) {
    if (identical(owner, _turnOwner)) cancel();
  }

  void cancel() {
    if (!state.isGenerating) return;
    _turns.active?.cancel();
    state = state.copyWith(notice: _t.noticeStopping);
  }

  /// Shortens the largest tool results (in place, keeping their beginning)
  /// until the prompt fits. Returns a notice when something was cut.
  Future<String?> fitToolResults(
    TextEngine engine,
    List<Map<String, Object>> messages,
    List<Map<String, Object>> toolMessages,
    InferenceSettings settings,
    ModelInfo model, {
    List<ToolSpec> tools = const [],
  }) => _fitToolResults(
    engine,
    messages,
    toolMessages,
    settings,
    model,
    tools: tools,
  );

  /// Shortens attached document text in the last user turn until the prompt
  /// fits (the largest file each round, keeping its passages closest to the
  /// request). Returns a notice when something was left out.
  ///
  /// [fullTexts] provides the complete extracted text for each attachment by
  /// filename, so semantic fitting can rank from the original document instead
  /// of the already-lexically-filtered prompt text (audit A03).
  Future<String?> fitDocuments(
    TextEngine engine,
    List<Map<String, Object>> messages,
    InferenceSettings settings,
    ModelInfo model, {
    Map<String, String>? fullTexts,
  }) => _fitDocuments(engine, messages, settings, model, fullTexts: fullTexts);

  static String _argSummary(ToolCall call) {
    final a = call.args;
    final v = a['query'] ?? a['url'] ?? a['expression'];
    if (v == null) return '';
    final text = '$v';
    return ' (${text.length > 48 ? '${text.substring(0, 45)}…' : text})';
  }

  static const storedExcerptChars = 12000;

  static String _sharedSourceLine(Map source, {required String separator}) {
    final label = source['sponsored'] == true
        ? '[sponsored — not used]'
        : '[${source['number']}]';
    return '$label ${source['title']}$separator${source['url']}';
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(
  ChatNotifier.new,
);
