import 'dart:async';
import 'dart:convert';
import 'dart:math';
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
import '../../../attachments/data/attachment_store.dart';
import '../../../attachments/domain/attachment.dart';
import '../../../knowledge/knowledge_embedder.dart';
import '../../../knowledge/knowledge_store.dart';
import '../../../retrieval/claim_check_runner.dart';
import '../../../retrieval/domain/claim_check.dart';
import '../../../retrieval/domain/date_check.dart';
import '../../../retrieval/semantic_rerank.dart';
import '../../../retrieval/support_check.dart';
import '../../../memory/domain/user_memory.dart';
import '../../domain/message_deletion.dart';
import '../../domain/conversation_workspace.dart';
import '../../domain/temporary_files.dart';
import '../../domain/context_summary.dart';
import '../../domain/turn_coordinator.dart';
import '../../../memory/presentation/providers/memory_provider.dart';
import '../../../../inference/engine/text_engine.dart';
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

part 'chat_web.dart';
part 'chat_branches.dart';
part 'chat_memory.dart';
part 'chat_export.dart';
part 'chat_turn.dart';

class ChatState {
  final List<ChatMessage> messages;
  final bool isGenerating, isLoadingModel;
  final ReasoningBlock? reasoning;
  final String partialAnswer;
  final String? error, chatId, notice;
  final Map<String, dynamic> metrics;
  final bool temporary;

  /// Facts the memory feature just stored from the last message, for the
  /// compact banner with its edit/discard affordance.
  final List<Memory> learned;
  const ChatState({
    this.messages = const [],
    this.isGenerating = false,
    this.isLoadingModel = false,
    this.reasoning,
    this.partialAnswer = '',
    this.error,
    this.chatId,
    this.notice,
    this.metrics = const {},
    this.learned = const [],
    this.temporary = false,
  });
  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isGenerating,
    bool? isLoadingModel,
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
  }) => ChatState(
    messages: messages ?? this.messages,
    isGenerating: isGenerating ?? this.isGenerating,
    isLoadingModel: isLoadingModel ?? this.isLoadingModel,
    reasoning: clearReasoning ? null : reasoning ?? this.reasoning,
    partialAnswer: partialAnswer ?? this.partialAnswer,
    error: clearError ? null : error ?? this.error,
    chatId: chatId ?? this.chatId,
    notice: clearNotice ? null : notice ?? this.notice,
    metrics: metrics ?? this.metrics,
    learned: learned ?? this.learned,
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
    with _ChatWeb, _ChatBranches, _ChatMemory, _ChatExport {
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
    ref.onDispose(() {
      _alive = false;
      _turns.dispose();
      engine.cancel();
      remote.cancel();
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
    await (db.update(db.chats)..where((t) => t.id.equals(id))).write(
      ChatsCompanion(overridesJson: drift.Value(jsonEncode(clean))),
    );
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
    final db = ref.read(appDatabaseProvider);
    // Attached files live outside the database; remove them with the chat.
    for (final row in await db.getMessages(id)) {
      for (final a in Attachment.listFromJson(
        jsonDecode(row.attachmentsJson),
      )) {
        await AttachmentStore.delete(a);
      }
    }
    await db.deleteChat(id);
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
  }) async {
    input = input.trim();
    if (_naming case final naming?) {
      // A late title gives way to the next turn; it is tried again later.
      _namingStopped = true;
      ref.read(llamaEngineProvider).cancel();
      await naming;
    }
    if (state.isGenerating ||
        (input.isEmpty && attachments.isEmpty) ||
        ref.read(modelManagerProvider).isLoadingModel) {
      return false;
    }
    final localEngine = ref.read(llamaEngineProvider);
    final remoteEngine = ref.read(remoteEngineProvider);
    final lease = _turns.begin(() {
      localEngine.cancel();
      remoteEngine.cancel();
    });
    _spoken = spoken;
    state = state.copyWith(
      isGenerating: true,
      clearError: true,
      clearReasoning: true,
      partialAnswer: '',
      notice: '',
      learned: const [],
    );
    ref.read(sessionBusyProvider.notifier).state = true;
    final t = _Turn(
      input,
      db: _database,
      localEngine: localEngine,
      lease: lease,
      insertUser: insertUser,
      resume: resume,
      attachments: attachments,
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
    );
    if (resume != null) {
      // The saved partial answer is both the display prefix and the model's
      // prefill; only new text streams in.
      t.answer.write(resume.content);
      t.tail.add(resume.content);
      if (resume.reasoning != null) t.thinking.write(resume.reasoning);
      state = state.copyWith(
        messages: state.messages.where((m) => m.id != resume.id).toList(),
        partialAnswer: resume.content,
      );
    }
    final remainingTime = budget?.remainingTime;
    if (remainingTime != null) {
      t.deadline = Timer(
        remainingTime < Duration.zero ? Duration.zero : remainingTime,
        cancel,
      );
    }
    _fittedOmitted = 0;
    try {
      final asked = await _prepareTurn(t);
      if (asked == null) return t.accepted;
      final planned = await _planRetrieval(t, asked.user);
      if (planned == null) return t.accepted;
      final found = await _lookUp(t, asked, planned);
      if (found == null) return t.accepted;
      final prompt = await _assemblePrompt(t, asked.user, planned, found);
      if (prompt == null) return t.accepted;
      await _startAnswer(t, prompt);
      await _runRounds(t, prompt);
      await _searchAfterRecall(t, asked, planned);
    } catch (e) {
      t.failure = '$e';
    } finally {
      await _endTurn(t);
    }
    return t.accepted;
  }

  /// The turn's settings and model, then the saved question. Null when the
  /// turn stops first: stopped, or the phone's model busy serving another
  /// device.
  Future<_Asked?> _prepareTurn(_Turn t) async {
    final input = t.input;
    final manager = ref.read(modelManagerProvider.notifier);
    await _temporaryReady;
    await ref.read(conversationWorkspaceProvider.notifier).ready;
    if (state.chatId != null && !state.temporary) {
      _projectId = ref
          .read(conversationWorkspaceProvider)
          .memberships[state.chatId];
    }
    await ref.read(settingsProvider.notifier).ready;
    t.budget?.check();
    await manager.ready;
    await ref.read(presetsProvider.notifier).ready;
    await ref.read(modelProfilesProvider.notifier).ready;
    await ref.read(adaptersProvider.notifier).ready;
    await ref.read(chatModelPinsProvider.notifier).ready;
    // The settings cascade for this turn (roadmap P1.4): your settings →
    // the model's profile → the active preset (FX-03) → this chat → this
    // turn. The preset's instructions join the system prompt later.
    final preset = ref.read(presetsProvider).active;
    final library = ref.read(modelManagerProvider);
    // A model pinned to this chat wins over the picker (when it is still
    // downloaded).
    final candidate =
        t.compareWith ??
        pinnedModel(state.chatId) ??
        library.loadedModel ??
        library.catalog.where((m) => m.isDownloaded).firstOrNull;
    final project = ref
        .read(conversationWorkspaceProvider)
        .projects
        .where((p) => p.id == _projectId)
        .firstOrNull;
    final resolved = t.resolved = resolveSettings(
      global: ref.read(settingsProvider),
      defaults: ref.read(settingsProvider.notifier).defaults,
      profiles: ref.read(modelProfilesProvider),
      preset: preset,
      chat: ref.read(chatOverridesProvider),
      recommendations: ref.read(modelRecommendationsProvider),
      project: project == null || project.collection.isEmpty
          ? const {}
          : {'knowledgeCollection': project.collection},
      projectLabel: project?.name ?? 'Project',
      model: candidate,
      turn: t.turnOverrides,
    );
    // Battery saver: a lighter local turn when the battery is low or the
    // phone is hot (nothing that would reload the model changes).
    final base = resolved.effective;
    final saverReason = t.saverReason = BatterySaver.reason(
      base,
      base.batterySaver && !base.usesRemote ? await DevicePower.read() : null,
    );
    var settings = saverReason == null ? base : BatterySaver.apply(base);
    if (state.temporary) settings = settings.copyWith(memoryEnabled: false);
    if (t.localOnly && settings.usesRemote) {
      settings = settings.copyWith(remoteEnabled: false);
    }
    if (saverReason != null) {
      state = state.copyWith(notice: BatterySaver.notice(saverReason, _t));
    }
    // Remote brain (decision 2026-10-18): a remote model is bigger
    // than the phone's rules and judge, so it decides itself whether to
    // search, what to search for and which pages to read, through the web
    // tools. Gemma on the Gemini API, a model that refused tools and Goal
    // steps keep the app's planning.
    final remoteBrain = t.remoteBrain =
        settings.usesRemote &&
        settings.webSearchEnabled &&
        settings.remoteWebResearch &&
        RemoteEngine.acceptsTools(settings) &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        t.answerSources == null &&
        t.compareWith == null &&
        // Goal steps keep their own guarded research (subject lock, read
        // budgets, checks).
        !t.forceResearch &&
        !t.localOnly &&
        !settings.structuredOutput;
    if (remoteBrain) {
      settings = settings.copyWith(
        toolsEnabled: true,
        toolWeb: true,
        toolMaxRounds: max(
          settings.toolMaxRounds,
          TurnPrompts.remoteBrainRounds,
        ),
      );
    }
    // The connection's own sampling, length and context (decision
    // 2026-10-18), unless its profile turned that off.
    if (settings.usesRemote &&
        (settings.activeRemoteProfile?.serverSettings ?? false)) {
      settings = settings.copyWith(serverSampling: true);
    }
    t.settings = settings;
    if (settings.usesRemote) {
      // The user's own server does the inference; no local model needed.
      t.engine = ref.read(remoteEngineProvider);
      final model = ModelInfo(
        id: 'remote:${settings.remoteModel.trim()}',
        displayName: settings.remoteModel.trim().isEmpty
            ? 'server default'
            : settings.remoteModel.trim(),
        fileName: '',
        sizeBytes: 0,
        family: ModelFamily.other,
        quantization: ModelQuantization.fp16,
      );
      t.model = model;
      t.modelId = model.id;
      t.stage('loadMs');
      state = state.copyWith(metrics: t.engine.metrics);
    } else {
      final model = candidate;
      if (model == null) throw StateError(_t.chatErrorNoModel);
      t.model = model;
      t.modelId = model.id;
      // This phone may be serving its model to another device: the chat
      // shares that model and waits for a request in progress.
      if (!await _shareWithHosting(model)) return null;
      state = state.copyWith(isLoadingModel: true);
      await manager.loadModel(model, forChat: true, settings: settings);
      t.stage('loadMs');
      state = state.copyWith(isLoadingModel: false, metrics: t.engine.metrics);
    }
    if (_cancelled) return null;
    final saved = await _saveQuestion(
      input,
      attachments: t.attachments,
      insertUser: t.insertUser,
      parentId: t.parentId,
      resume: t.resume,
      modelId: t.modelId,
    );
    if (state.temporary) {
      await TemporaryFiles.remember(t.attachments.map((a) => a.path));
    }
    final user = saved.user;
    t.chatId = saved.chatId;
    t.sourceMessageId = user.id;
    t.sequence = saved.sequence;
    t.accepted = true;
    // Scan each saved user message even if generation later stops or fails.
    if (t.insertUser &&
        t.resume == null &&
        t.learn &&
        !state.temporary &&
        ref.read(settingsProvider).memoryEnabled) {
      final captured = await _learnExplicit(
        input,
        chatId: saved.chatId,
        sourceMessageId: user.id,
      );
      if (_alive && captured != null && captured.isNotEmpty) {
        state = state.copyWith(learned: captured);
      }
    }
    t.answerParent =
        t.resume?.parentId ?? (t.insertUser ? user.id : _lastLiveUser?.id);
    return (user: user, preset: preset);
  }

  /// What the turn looks up: the question's own plan, then what a
  /// follow-up adds (pages this chat read, the earlier subject, a new
  /// search). Null when the turn was stopped.
  Future<_Planned?> _planRetrieval(_Turn t, ChatMessage user) async {
    final input = t.input;
    final settings = t.settings!;
    final remoteBrain = t.remoteBrain;
    final webAllowed =
        settings.webSearchEnabled &&
        (!settings.usesRemote || settings.remoteWebResearch);
    var plan = RetrievalPlan.of(
      input,
      // A continuation keeps its original context; no new retrieval. A
      // comparison reuses the original answer's evidence below.
      webEnabled:
          webAllowed &&
          !remoteBrain &&
          t.resume == null &&
          t.reuseSourcesJson == null &&
          t.promptOverride == null,
      // Always searches every message except a greeting, which has no
      // question in it.
      always:
          t.forceResearch ||
          (settings.webMode == WebMode.always &&
              !RetrievalPlan.greetingOnly(input) &&
              !RetrievalPlan.aboutAssistant(input)),
    );
    if (t.reuseSourcesJson case final reused?) {
      final stored = SearchSteps.sourcesFromJson(reused);
      t.sources = stored.where((s) => !s.sponsored).toList();
      t.sponsored = stored.where((s) => s.sponsored).toList();
    }
    // Follow-ups look at what this chat already read before anything else
    // (the page memory): "tell me more about the second story" needs that
    // story's article and "why?" the last answer's evidence — not a web
    // search for the words "second story".
    // A chain of follow-ups keeps the question that named the subject: the
    // third "and the battery?" after "what about its price?" is still about
    // the camera of the first question (report 2026-10-04).
    final previousQuestion = RetrievalPlan.conversationTopic([
      for (final m in state.messages)
        if (m.role == ChatRole.user && isLive(m) && m.id != user.id) m.content,
    ]);
    final contextual = previousQuestion == null
        ? input
        : RetrievalPlan.withContext(
            input,
            previousQuestion,
            previousAnswer: _lastLiveAssistant?.content,
          );
    t.askedInContext = contextual;
    // "Are you able to do online searches?" is answered about the
    // assistant, not searched (report 2026-10-07).
    final selfQuestion =
        !t.forceResearch &&
        RetrievalPlan.aboutAssistant(
          input,
          afterQuestion: previousQuestion != null,
        );
    if (selfQuestion && plan.mode != RetrievalMode.readUrls) {
      plan = RetrievalPlan(
        mode: RetrievalMode.none,
        urls: const [],
        query: plan.query,
        wantsWeb: false,
      );
    }
    var recalledTurn = false;
    var followUpSearch = false;
    if (!selfQuestion &&
        !remoteBrain &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        !t.isolated &&
        previousQuestion != null &&
        plan.mode != RetrievalMode.readUrls &&
        RetrievalPlan.looksLikeFollowUp(input) &&
        !_cancelled) {
      final recalled = await _recall(
        input,
        previousQuestion: previousQuestion,
        settings: settings,
        webAllowed: webAllowed,
        operationBudget: t.budget,
      );
      if (_cancelled || !_alive) return null;
      t.stage('recallMs');
      if (recalled.isNotEmpty) {
        t.sources = recalled;
        recalledTurn = true;
        t.searchIfLacking = webAllowed;
        plan = RetrievalPlan(
          mode: RetrievalMode.none,
          urls: const [],
          query: contextual,
          wantsWeb: plan.wantsWeb,
        );
        final fresh = recalled.where((s) => !s.remembered).length;
        state = state.copyWith(
          notice: fresh > 0
              ? _t.noticeRecallArticle(recalled.length - fresh)
              : _t.noticeRecallPages(recalled.length),
        );
      } else if (plan.mode == RetrievalMode.search) {
        // Search for what the follow-up is about, not for its pronouns.
        plan = RetrievalPlan(
          mode: plan.mode,
          urls: plan.urls,
          query: contextual,
          wantsWeb: plan.wantsWeb,
        );
      } else if (NewsIntent.of(previousQuestion) != null &&
          NewsIntent.of(contextual) != null &&
          webAllowed) {
        // "What about sports?" after a briefing is still a news question.
        plan = RetrievalPlan.of(contextual, webEnabled: true, always: true);
      } else if (webAllowed &&
          AnswerChecks.asksFact.hasMatch(input) &&
          // "What is 5 times that?" and "What's my name?" are the chat's.
          MathQuestion.expression(input) == null &&
          !AboutUser.asks(input) &&
          !RetrievalPlan.aboutAssistant(input) &&
          !AnswerChecks.notAFact.hasMatch(input) &&
          state.messages.any(
            (m) =>
                m.role == ChatRole.assistant &&
                isLive(m) &&
                m.sourcesJson.trim().startsWith('[{') &&
                SearchSteps.sourcesFromJson(
                  m.sourcesJson,
                ).any((s) => !s.sponsored),
          )) {
        // A follow-up in a chat that read the web, which the pages read do
        // not cover, searches again: Gemma 4 E2B guessed "300 to 400 shots"
        // for the Z30's battery (app quality probe, 2026-10-19).
        plan = RetrievalPlan.of(contextual, webEnabled: true, always: true);
        // Shown while it searches (tester, 2026-10-19).
        followUpSearch = plan.mode == RetrievalMode.search;
      }
    }
    return (
      plan: plan,
      contextual: contextual,
      previousQuestion: previousQuestion,
      selfQuestion: selfQuestion,
      recalledTurn: recalledTurn,
      followUpSearch: followUpSearch,
    );
  }

  /// Runs the plan: the judge (a hosted model's "does this need the
  /// web?"), the search itself, and Wikipedia for a stable fact. Null when
  /// the turn was stopped.
  Future<_Found?> _lookUp(_Turn t, _Asked asked, _Planned planned) async {
    final input = t.input;
    final settings = t.settings!;
    final engine = t.engine;
    final model = t.model!;
    final remoteBrain = t.remoteBrain;
    final user = asked.user;
    var plan = planned.plan;
    // The part of the system prompt every path shares. Built before the
    // judge so the judge's prompt is a prefix-compatible extension of the
    // real turn: the engine then keeps the conversation's KV cache instead
    // of prefilling the whole chat twice (report: search feels slow).
    // The judge gets an ordinary turn's notes, the more common outcome.
    final shared = await _baseSystem(
      input,
      settings: settings,
      preset: asked.preset,
      extraSystem: t.extraSystem,
    );
    t.memoryFacts = shared.facts;
    // Auto: when no keyword fired, let a hosted model judge whether the
    // question needs current or external information. Otherwise a model
    // that was never handed sources truthfully says it cannot browse (tester
    // report). Not on the phone ([TurnPolicy.judgeLocalModels]).
    if (plan.mode == RetrievalMode.none &&
        settings.webMode == WebMode.auto &&
        (settings.usesRemote || TurnPolicy.judgeLocalModels) &&
        !remoteBrain &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        !planned.recalledTurn &&
        !planned.selfQuestion &&
        !RetrievalPlan.smallTalk(input) &&
        !RetrievalPlan.localTask(input) &&
        // The attached file is the source for this turn. Explicit web and
        // timely requests already set plan.mode above and still search.
        !t.attachments.any((a) => !a.isImage) &&
        t.budget == null &&
        !_cancelled) {
      state = state.copyWith(notice: _t.noticeCheckingSearch);
      if (await _needsWeb(
        engine,
        model,
        settings,
        input,
        system: '${shared.system}${shared.notes}',
        // Rendered exactly as the answering turn will render them, so the
        // two prompts share their prefix.
        history: [
          for (final m in state.messages.where(isLive))
            if (m.id != user.id)
              TurnPrompts.renderTurn(
                m,
                vision: settings.usesRemote
                    ? settings.remoteVision
                    : engine.metrics['supportsVision'] == true,
                documents: !settings.usesRemote || settings.remoteDocuments,
                documentQuestion: input,
              ),
        ],
      )) {
        plan = RetrievalPlan.of(
          planned.contextual,
          webEnabled: true,
          always: true,
        );
      }
      t.stage('judgeMs');
      if (_cancelled || !_alive) return null;
    }
    // "Where I live", "near me": the place the user named in this chat,
    // not wherever a result page locates the phone.
    if (plan.mode == RetrievalMode.search) {
      final placed = RetrievalPlan.withUserPlace(plan.query, [
        for (final m in state.messages)
          if (m.role == ChatRole.user && isLive(m) && m.id != user.id)
            m.content,
      ]);
      if (placed != plan.query) {
        plan = RetrievalPlan(
          mode: plan.mode,
          urls: plan.urls,
          query: placed,
          wantsWeb: plan.wantsWeb,
        );
      }
    }
    final timely = plan.wantsWeb;
    // Model-driven research (overhaul phase 2): a question that would be
    // searched goes to the tool loop instead; pasted links are still read
    // directly. The first round must call a tool.
    final researchTurn =
        settings.researchLoop &&
        settings.toolsEnabled &&
        settings.toolWeb &&
        !settings.structuredOutput &&
        plan.mode == RetrievalMode.search &&
        t.resume == null &&
        t.reuseSourcesJson == null;
    if (researchTurn) {
      plan = RetrievalPlan.of(plan.query, webEnabled: false);
      state = state.copyWith(notice: _t.noticeResearchingTools);
    }
    if (researchTurn || plan.mode == RetrievalMode.search) {
      t.lease.transition(TurnStage.researching);
    }
    final web = await _gatherWeb(
      plan,
      settings: settings,
      engine: engine,
      model: model,
      sources: t.sources,
      sponsored: t.sponsored,
      timely: timely,
      researchTurn: researchTurn,
      recalledTurn: planned.recalledTurn,
      followUpSearch: planned.followUpSearch,
      stage: t.stage,
      subject: t.subject,
      subjectAllowed: t.subjectAllowed,
      operationBudget: t.budget,
      earlier: planned.contextual == input ? null : planned.previousQuestion,
    );
    if (web == null) return null;
    t.sources = web.sources;
    // Web search off: an imported offline Wikipedia still answers a factual
    // question about a subject it has an article on.
    if (t.sources.isEmpty &&
        !settings.webSearchEnabled &&
        !researchTurn &&
        plan.mode == RetrievalMode.none &&
        t.resume == null &&
        t.attachments.isEmpty &&
        RetrievalPlan.encyclopedic(input)) {
      final article = await _offlineWikipedia(input);
      if (_cancelled || !_alive) return null;
      if (article != null) t.sources = [article];
    }
    // Web search on, nothing searched: a stable fact the phone's small
    // model would answer from memory gets the subject's Wikipedia article
    // (offline archive first). Qwen3.5 0.8B answered "Sydney" for
    // Australia's capital (phone probe, 2026-10-18) and "born in Paris" for
    // Marie Curie (D1 benchmark, 2026-10-11); a remote model decides for
    // itself.
    if (t.sources.isEmpty &&
        AnswerChecks.wikipediaFactCheck(
          input,
          webOn: settings.webSearchEnabled,
          remote: engine is RemoteEngine || remoteBrain,
        ) &&
        !researchTurn &&
        !planned.selfQuestion &&
        !planned.recalledTurn &&
        plan.mode == RetrievalMode.none &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        t.attachments.isEmpty &&
        t.budget == null) {
      state = state.copyWith(notice: _t.noticeCheckingWikipedia);
      final article = await _joinWikipedia(_wikipedia(input, settings));
      t.stage('wikipediaMs');
      if (_cancelled || !_alive) return null;
      if (article != null) t.sources = [article];
      if (state.notice == _t.noticeCheckingWikipedia) {
        state = state.copyWith(clearNotice: true);
      }
    }
    if (plan.mode == RetrievalMode.search) t.searchQueries = web.queries;
    t.sponsored = web.sponsored;
    t.newsAnswer = web.newsTurn;
    if (_cancelled) return null;
    return (
      plan: plan,
      shared: shared,
      timely: timely,
      researchTurn: researchTurn,
      queries: web.queries,
      newsIntent: web.newsIntent,
      newsTurn: web.newsTurn,
    );
  }

  /// What the model is given: the system prompt, the chat as it fits, the
  /// documents, the knowledge library and the web evidence. Null when the
  /// turn was stopped.
  Future<_Prompt?> _assemblePrompt(
    _Turn t,
    ChatMessage user,
    _Planned planned,
    _Found found,
  ) async {
    final input = t.input;
    final settings = t.settings!;
    final engine = t.engine;
    final model = t.model!;
    final shared = found.shared;
    final researchTurn = found.researchTurn;
    // A turn that researches keeps only pinned notes and how to answer: a
    // note that merely shares a word with the question would steer its
    // searches and its report (review #10, round 3).
    final researching = researchTurn || found.plan.mode == RetrievalMode.search;
    t.usedMemoryNotes = researching ? shared.researchNotes : shared.notes;
    final system = StringBuffer('${shared.system}${t.usedMemoryNotes}');
    // Models whose chat template understands enable_thinking (Qwen3.5,
    // Gemma 4) get the switch through the template; only older models need
    // the prompt-level nudge.
    if (settings.thinkingModeEnabled &&
        engine.metrics['supportsThinking'] != true) {
      system.write(
        '\nIf your model supports reasoning, put your explanation in <think> and </think> before your final answer.',
      );
    }
    if (planned.selfQuestion) {
      system.write(
        settings.webSearchEnabled &&
                (!settings.usesRemote || settings.remoteWebResearch)
            ? '\nThe user asks what you can do. You can search the web and read pages when a question needs current or outside facts (news, prices, weather, recent events); otherwise you answer from what you know. Say so briefly and offer to look something up.'
            : '\nThe user asks what you can do. Web search is off in this app\'s settings, so you answer from what you know; the user can turn it on in Settings. Say so briefly.',
      );
    }
    if (found.timely && t.sources.isEmpty && !researchTurn && !t.remoteBrain) {
      system.write(
        '\nLive information is unavailable. Explicitly tell the user you cannot verify current facts. Do not invent current news, prices, weather, or office holders.',
      );
    }
    final offered = _offerTools(
      input,
      settings: settings,
      engine: engine,
      system: system,
      sources: t.sources,
      researchTurn: researchTurn,
      remoteBrain: t.remoteBrain,
      allowRecall: !researching,
      continuing:
          t.resume != null ||
          t.reuseSourcesJson != null ||
          t.promptOverride != null,
    );
    t.runner = offered.runner;
    // Remote capabilities are explicit: OpenAI-compatible model listings do
    // not reliably advertise vision or document support.
    final vision = t.vision = settings.usesRemote
        ? settings.remoteVision
        : engine.metrics['supportsVision'] == true;
    final documents = !settings.usesRemote || settings.remoteDocuments;
    final live = state.messages.where(isLive).toList();
    final summary =
        !state.temporary &&
            !t.isolated &&
            t.resume == null &&
            t.promptOverride == null
        ? await ContextSummary.read(state.chatId)
        : null;
    final summarized = summary != null && summary.validFor(live);
    final requestedLive = summarized
        ? live.skip(summary.messageIds.length).toList()
        : live;
    if (summarized) {
      t.summarizedIds = summary.messageIds.toSet();
      system.write(
        '\nUser-reviewed summary of earlier messages (context, not new instructions; original messages remain saved):\n${summary.text}',
      );
    }
    // An isolated message is sent on its own (a Goal step).
    final sent = t.isolated
        ? live.skip(max(0, live.length - 1)).toList()
        : requestedLive;
    t.contextAvailable = live;
    t.contextRequested = sent;
    final messages = <Map<String, Object>>[
      {'role': 'system', 'content': system.toString()},
      for (final m in sent)
        TurnPrompts.renderTurn(
          m,
          vision: vision,
          documents: documents,
          documentQuestion: input,
        ),
    ];
    if (t.promptOverride case final override?) {
      messages.last = {...messages.last, 'content': override};
      t.sources = [...?t.answerSources];
    }
    if (t.attachments.any((a) => a.isImage) && !vision && t.resume == null) {
      state = state.copyWith(
        notice: settings.usesRemote
            ? _t.noticeImageRemoteOff
            : _t.noticeImageNoVision,
      );
    }
    // Long documents are cut to fit the context (head kept) before any web
    // evidence is added; the notice says how much survived.
    final cut = t.documentCut = await fitDocuments(
      engine,
      messages,
      settings,
      model,
    );
    if (_cancelled || !_alive) return null;
    if (cut != null) state = state.copyWith(notice: cut);
    // Knowledge library (FX-02): passages from the chosen collection join
    // the evidence ahead of any web pages; a continuation or comparison
    // keeps what its original turn saw.
    if (settings.knowledgeCollection.isNotEmpty &&
        t.resume == null &&
        t.reuseSourcesJson == null &&
        t.promptOverride == null &&
        input.isNotEmpty) {
      final own = await ref
          .read(knowledgeStoreProvider)
          .search(
            settings.knowledgeCollection,
            input,
            maxPassages: settings.evidencePassages,
          );
      if (_cancelled || !_alive) return null;
      if (own.isNotEmpty) {
        t.sources = [...own, ...t.sources];
        state = state.copyWith(
          notice:
              '${_t.noticeKnowledgeDocs(own.length, settings.knowledgeCollection)}'
              '${t.sources.length > own.length ? _t.noticePlusWebResults(t.sources.length - own.length) : ''}.',
        );
      }
    }
    final fitted = await _fitEvidence(
      input,
      messages,
      system: system.toString(),
      sources: t.sources,
      plan: found.plan,
      queries: found.queries,
      // The answer's settings: reasoning needs its room kept when the
      // evidence is fitted.
      settings: TurnPolicy.groundedSettings(
        settings,
        grounded: t.sources.isNotEmpty,
      ),
      engine: engine,
      model: model,
      newsTurn: found.newsTurn,
      newsIntent: found.newsIntent,
      recalledTurn: planned.recalledTurn,
      comparison: t.reuseSourcesJson != null,
      overridden: t.promptOverride != null,
      prefix: t.resume?.content ?? '',
    );
    if (fitted == null) return null;
    t.sources = fitted;
    t.contextInstructions = messages.first['content'] as String;
    t.stage('budgetMs');
    final sum = _addTurnNotes(t, messages, user: user, clock: offered.clock);
    // Tool results number their sources after the evidence already in the
    // prompt, so every [n] means one source.
    t.runner?.seed(t.sources);
    return (
      messages: messages,
      tools: offered.tools,
      nativeTools: offered.native,
      researchTurn: researchTurn,
      sum: sum,
    );
  }

  /// What the app adds to the question itself: the sum it worked out, the
  /// "these are the user's facts" note, the clock line. A spoken phone turn
  /// may get the app's own answer instead ([_Turn.appAnswer]). Returns the
  /// sum's note, if the question was plain arithmetic.
  String? _addTurnNotes(
    _Turn t,
    List<Map<String, Object>> messages, {
    required ChatMessage user,
    required bool clock,
  }) {
    final input = t.input;
    final settings = t.settings!;
    final local = t.engine is! RemoteEngine;
    // Plain arithmetic is worked out by the app: the 0.8B and a remote
    // Gemma 4 E4B both answered 15 + 27 wrongly without thinking
    // (conversation probe, 2026-10-18).
    final asked = [
      for (final m in state.messages)
        if (m.role == ChatRole.user && isLive(m) && m.id != user.id) m.content,
    ];
    final sum = MathQuestion.note(input, earlier: asked);
    // Said as the app worked it out on any spoken turn: given "= 84", LM
    // Studio Gemma 4 E4B answered "Eighty-four doubled again is one hundred
    // sixty-eight" (phone probe round 5, 2026-10-18).
    // What the user tells about themself is saved by the explicit-fact
    // capture when the turn starts.
    final remembers =
        t.learn && t.insertUser && !state.temporary && settings.memoryEnabled;
    if (t.spoken) {
      t.appAnswer =
          MathQuestion.spoken(input, earlier: asked) ??
          (local
              ? AboutUser.spokenName(input, asked) ??
                    AboutUser.spokenFact(input, asked) ??
                    AboutUser.spokenNames(input, asked) ??
                    AboutUser.spokenIntro(input) ??
                    AboutUser.spokenNoted(input, remembered: remembers) ??
                    AboutUser.spokenGreeting(input) ??
                    AboutUser.spokenAbilities(
                      input,
                      web: settings.webSearchEnabled,
                    )
              : null);
    }
    // "What's my name?": the phone's small model answered as if the user's
    // facts were its own.
    final note = [
      ?sum,
      if (!t.remoteBrain && AboutUser.asks(input)) AboutUser.note,
      if (t.appAnswer == null)
        ?AboutUser.statedNote(input, remembered: remembers),
    ].join(' ');
    if (local && AboutUser.asks(input)) t.aboutUser = asked;
    if (note.isNotEmpty &&
        messages.last['role'] == 'user' &&
        messages.last['content'] is String) {
      messages.last = {
        ...messages.last,
        'content': '${messages.last['content']}\n\n$note',
      };
    }
    final request = messages.last['content'];
    if (clock &&
        messages.last['role'] == 'user' &&
        request is String &&
        !request.startsWith('Today is')) {
      messages.last = {
        ...messages.last,
        'content': '${TurnPrompts.clockLine()}\n\n$request',
      };
    }
    return sum;
  }

  /// CHAT-01: the assistant row exists before the first token, so a kill
  /// mid-answer leaves an interrupted message, not a missing one. Then the
  /// timers that save and paint the answer as it streams.
  Future<void> _startAnswer(_Turn t, _Prompt prompt) async {
    final db = t.db;
    final status = t.compareWith == null
        ? 'generating'
        : 'alternative:generating';
    t.newParser();
    if (t.resume != null) {
      await db.updateMessage(
        t.assistantId,
        MessagesCompanion(status: drift.Value(status)),
      );
    } else {
      await db.insertMessage(
        MessagesCompanion.insert(
          id: t.assistantId,
          chatId: t.chatId!,
          role: 'assistant',
          content: '',
          timestamp: DateTime.now(),
          sequence: t.sequence + 1,
          status: drift.Value(status),
          sourcesJson: drift.Value(
            jsonEncode(_sourceMaps(t.displayedSources())),
          ),
          modelId: drift.Value(t.modelId),
          parentId: drift.Value(t.answerParent),
        ),
      );
    }
    t.placeholderSaved = true;
    final answer = t.answer, thinking = t.thinking;
    var checkpointed = 0;
    t.checkpoint = Timer.periodic(checkpointInterval, (_) {
      final length = answer.length + thinking.length;
      if (length == checkpointed || !_alive) return;
      checkpointed = length;
      // Serialize writes so a late checkpoint cannot overwrite the final row.
      t.pendingWrite = t.pendingWrite.then(
        (_) => db.updateMessage(
          t.assistantId,
          MessagesCompanion(
            content: drift.Value(answer.toString()),
            reasoning: drift.Value(
              thinking.isEmpty ? null : thinking.toString(),
            ),
          ),
        ),
        onError: (_) {},
      );
    });
    final reasoningId = const Uuid().v4();
    final tools = prompt.tools;
    var painted = (-1, -1);
    t.repaint = Timer.periodic(repaintInterval, (_) {
      // Nothing new since the last frame (prefill, a tool running): no
      // state change, so nothing listening to the stream rebuilds.
      final lengths = (answer.length, thinking.length);
      if (_alive && lengths != painted) {
        painted = lengths;
        state = state.copyWith(
          // A tool call being written is not part of the answer.
          partialAnswer: tools.isEmpty
              ? answer.toString()
              : ToolMarkup.visible(answer.toString()),
          reasoning: thinking.isEmpty
              ? null
              : ReasoningBlock(id: reasoningId, content: thinking.toString()),
        );
      }
    });
  }

  /// Generation rounds: the model may end a round with tool calls; the
  /// host runs them, appends the results and asks again, at most
  /// toolMaxRounds times. Each round's text moves into the reasoning
  /// channel as a step so the final answer stays clean. A copied prompt, a
  /// denied figure and an unchecked live figure are each asked again once.
  Future<void> _runRounds(_Turn t, _Prompt prompt) async {
    final input = t.input;
    final settings = t.settings!;
    final engine = t.engine;
    final model = t.model!;
    final budget = t.budget;
    final runner = t.runner;
    final messages = prompt.messages;
    final tools = prompt.tools;
    final nativeTools = prompt.nativeTools;
    final local = engine is! RemoteEngine;
    final answer = t.answer, thinking = t.thinking;
    final toolMessages = <Map<String, Object>>[];
    var rounds = 0;
    // A model restating its whole answer is stopped at the repeat.
    var repeatStopped = false;
    // The model copied its prompt instead of answering; asked again once.
    var echoed = false;
    var echoRetried = false;
    // The answer said the figure asked for is unknown; asked once more.
    var denialRetried = false;
    // The answer gave a "next" date that has passed; asked once more.
    var pastRetried = false;
    Object? echoPrompt;
    var pieces = 0;
    // Out of tool rounds with calls still coming: one last round without
    // tools, answering from what was gathered (the call itself used to end
    // up as the answer).
    var lastRound = false;
    // The remote model offered to read on instead of reading; told yes
    // once.
    var toldToRead = false;
    while (true) {
      if (_cancelled) break;
      budget?.check();
      if (toolMessages.isNotEmpty) {
        // Tool results can outgrow the context (nine pages plus thinking did
        // on the phone); the bridge would then drop the question itself.
        // Shorten the largest results until the prompt fits.
        final roundPrompt = [...messages, ...toolMessages];
        final cut = await fitToolResults(
          engine,
          roundPrompt,
          toolMessages,
          settings,
          model,
          tools: nativeTools ? tools : const [],
        );
        messages.removeWhere((m) => !roundPrompt.contains(m));
        if (cut != null) thinking.write('\n$cut\n');
      }
      // A spoken phone answer gets the same cap: at the card's 1.0 the 0.8B
      // put Canberra "in New Zealand's northern island" and answered "¿qué
      // tal?" with nonsense (Conversation probe round 7, 2026-10-18).
      var roundSettings = TurnPolicy.groundedSettings(
        settings,
        grounded: t.sources.isNotEmpty || (t.spoken && local),
      );
      if (budget != null) {
        final preview = await engine.previewPrompt(
          messages: [...messages, ...toolMessages],
          fallbackTemplate: model.family.fallbackTemplate,
          settings: roundSettings,
          tools: nativeTools ? tools : const [],
        );
        final allowed = budget.outputAllowance(
          (preview['promptTokens'] as num?)?.toInt() ?? 0,
          roundSettings.outputCeiling,
        );
        roundSettings = roundSettings.withinOutput(allowed);
      }
      try {
        await for (final event in _turns.stream(
          t.lease,
          () => engine.generate(
            messages: [...messages, ...toolMessages],
            fallbackTemplate: model.family.fallbackTemplate,
            settings: roundSettings,
            assistantPrefix: t.resume?.content ?? '',
            tools: nativeTools ? tools : const [],
            // Required applies to the first round only; once a result is in,
            // the model must be free to answer. An outright action request
            // must prepare its card, not promise to.
            toolChoice:
                nativeTools && (lastRound || RetrievalPlan.smallTalk(input))
                ? 'none'
                : nativeTools &&
                      rounds == 0 &&
                      (prompt.researchTurn ||
                          (t.remoteBrain &&
                              settings.webMode == WebMode.always &&
                              !RetrievalPlan.greetingOnly(input)) ||
                          settings.toolChoice == ToolChoice.required ||
                          (PhoneActions.command(input) &&
                              tools.any(
                                (s) => PhoneActions.kinds.contains(s.name),
                              )))
                ? 'required'
                : 'auto',
          ),
        )) {
          if (event is! TextDelta) continue;
          t.parser!.add(event.text);
          if (_cancelled) engine.cancel();
          if (++pieces % 24 == 0 &&
              !repeatStopped &&
              AnswerCleanup.isRepeating(answer.toString())) {
            repeatStopped = true;
            engine.cancel();
          }
          // The model narrates the request on a new line: the answer is
          // over (stopped before the voice reaches that line).
          if (!repeatStopped && event.text.isNotEmpty && t.tail.narrating) {
            repeatStopped = true;
            engine.cancel();
          }
          // Checked while the answer's opening is being written, on a turn
          // with sources: their prompt opens with the app's own paragraphs,
          // while a chat turn's may be the user's text, which a corrected
          // copy starts with.
          // The second try is checked against the same sources turn.
          final asked = echoPrompt ??= messages.last['content'];
          if (!echoed &&
              !t.echoStopped &&
              t.resume == null &&
              t.sources.isNotEmpty &&
              answer.length >= 60 &&
              answer.length < 400 &&
              asked is String &&
              AnswerCleanup.echoes(answer.toString(), asked)) {
            if (echoRetried) {
              t.echoStopped = true;
            } else {
              echoed = true;
            }
            engine.cancel();
          }
        }
      } finally {
        final prompt = (engine.metrics['promptTokens'] as num?)?.toInt() ?? 0;
        final generated = (engine.metrics['tokens'] as num?)?.toInt() ?? 0;
        budget?.charge(prompt, generated);
        t.promptTokens += prompt;
        t.generatedTokens += generated;
        t.generationRounds++;
        t.nativeOmitted = max(
          t.nativeOmitted,
          (engine.metrics['trimmedMessages'] as num?)?.toInt() ?? 0,
        );
        t.metrics = {
          ...engine.metrics,
          'promptTokens': t.promptTokens,
          'tokens': t.generatedTokens,
          'generationRounds': t.generationRounds,
          'trimmedMessages': _fittedOmitted + t.nativeOmitted,
        };
      }
      // A copy of the prompt is no answer: once, ask again in a short turn
      // of its own after the cached prompt. The same order appended to the
      // end of the sources turn was copied too (frozen-web benchmark,
      // 2026-10-11: 3 of 3 on the weather tables).
      if (echoed && !echoRetried && !_cancelled && _alive) {
        echoRetried = true;
        echoed = false;
        t.parser!.close();
        final copied = answer.toString().trim().split('\n').first;
        t.clearAnswer();
        thinking.write('\n(The answer copied the prompt; asked again.)\n');
        final question = input.isEmpty ? 'the question above' : input;
        (toolMessages.isEmpty ? messages : toolMessages).addAll([
          {'role': 'assistant', 'content': copied},
          {
            'role': 'user',
            'content':
                'That copies the prompt. Answer in your own words, from '
                'the sources above, citing them like [1]: $question',
          },
        ]);
        t.newParser();
        continue;
      }
      // The phone's model says the figure is unknown while its pages give
      // one: once, ask again for it from them. Qwen3.5 0.8B said "There is
      // no current record of how many people live in Ottawa" (phone probe
      // round 6, 2026-10-18).
      if (!denialRetried &&
          !_cancelled &&
          _alive &&
          !repeatStopped &&
          !t.echoStopped &&
          t.resume == null &&
          local &&
          t.sources.isNotEmpty &&
          // A recalled page that lacks it: the turn searches instead
          // ([_searchAfterRecall]).
          !t.searchIfLacking &&
          AnswerCleanup.deniesFigure(answer.toString(), input) &&
          t.sources.any(
            (s) => RegExp(r'\d').hasMatch('${s.snippet} ${s.pageText ?? ''}'),
          )) {
        denialRetried = true;
        t.parser!.close();
        final denied = answer.toString().trim();
        t.clearAnswer();
        thinking.write(
          '\n(The answer said the figure is unknown; asked again.)\n',
        );
        (toolMessages.isEmpty ? messages : toolMessages).addAll([
          {'role': 'assistant', 'content': denied},
          {
            'role': 'user',
            'content':
                'The sources above do give a figure for this. Answer '
                'with it, citing them like [1]: $input',
          },
        ]);
        t.newParser();
        continue;
      }
      // "The next eclipse is on August 12, 2026" asked on October 20,
      // 2026: once, ask for the first date after today. Qwen3.5 0.8B took
      // the page's most recent date (speed set, 2026-10-20). The parser
      // holds back the answer's last characters until it is closed, and
      // every path from here closes it anyway.
      t.parser!.close();
      if (!pastRetried &&
          !_cancelled &&
          _alive &&
          !repeatStopped &&
          !t.echoStopped &&
          t.resume == null &&
          local &&
          t.sources.isNotEmpty &&
          DateCheck.passedNext(answer.toString(), input, DateTime.now())) {
        pastRetried = true;
        final dated = answer.toString().trim();
        t.clearAnswer();
        thinking.write(
          '\n(The answer gave a date already past; asked again.)\n',
        );
        final now = DateTime.now();
        final today =
            '${now.year}-${now.month.toString().padLeft(2, '0')}-'
            '${now.day.toString().padLeft(2, '0')}';
        (toolMessages.isEmpty ? messages : toolMessages).addAll([
          {'role': 'assistant', 'content': dated},
          {
            'role': 'user',
            'content':
                'That date has already passed: today is $today. Answer with '
                'the first date after today that the sources give, citing '
                'them like [1], or say they give none: $input',
          },
        ]);
        t.newParser();
        continue;
      }
      if (runner == null ||
          tools.isEmpty ||
          _cancelled ||
          repeatStopped ||
          t.echoStopped ||
          !_alive) {
        break;
      }
      // Flush the parser so the round's text is complete before reading it.
      t.parser!.close();
      final roundText = answer.toString();
      var calls = lastRound || (nativeTools && RetrievalPlan.smallTalk(input))
          ? const <ToolCall>[]
          : nativeTools
          ? TextEngine.toolCallsOf(engine.metrics)
          : TextToolProtocol.parse(roundText, counter: rounds + 1);
      // A plain timer request the phone's model answered with chat instead
      // of the required call is prepared from its own words.
      var appCall = false;
      if (calls.isEmpty &&
          rounds == 0 &&
          !lastRound &&
          local &&
          PhoneActions.command(input) &&
          tools.any((s) => s.name == 'set_timer')) {
        final timer = PhoneActions.plainTimer(input);
        if (timer != null) {
          calls = [
            ToolCall(
              id: 'app_timer',
              name: 'set_timer',
              arguments: jsonEncode(timer),
            ),
          ];
          appCall = true;
        }
      }
      // The round's words without any tool-call markup: the parser's own
      // split when the native library reports calls, else the known markers
      // (the text protocol only drops blocks that are calls).
      final stripped = nativeTools
          ? ToolMarkup.strip(roundText)
          : TextToolProtocol.strip(roundText);
      final said = appCall
          ? ''
          : calls.isNotEmpty &&
                nativeTools &&
                engine.metrics['toolContent'] is String
          ? (engine.metrics['toolContent'] as String).trim()
          : stripped;
      // A changing figure with nothing looked up this turn: "tomorrow in
      // Rome… twenty-eight degrees" from no page (round 5).
      // Only when the question asks for one: an explanation that names a
      // cost or a forecast was moved to the thinking pop-up and asked again,
      // and the second, shorter answer was the one shown (tester,
      // 2026-10-20: "it answered twice").
      final unchecked =
          rounds == 0 &&
          t.appAnswer == null &&
          prompt.sum == null &&
          t.sources.isEmpty &&
          (RetrievalPlan.timeSensitive(input) ||
              RetrievalPlan.productSpec(input)) &&
          AnswerCleanup.statesLiveFigure(said);
      // An age "as of" an earlier year, copied from a dated snippet.
      final dated =
          rounds > 0 && AnswerCleanup.staleAge(input, said, DateTime.now());
      if (calls.isEmpty &&
          t.remoteBrain &&
          !toldToRead &&
          !lastRound &&
          rounds < settings.toolMaxRounds &&
          (unchecked ||
              dated ||
              // A full answer that ends by pointing at a site is kept.
              (rounds > 0 &&
                  said.length < 600 &&
                  (AnswerCleanup.offersToLookFurther(said) ||
                      AnswerCleanup.defersToSources(said))))) {
        // "Would you like the specific details from Environment Canada?"
        // after a search (LM Studio Gemma 4 E4B, conversation probe
        // 2026-10-18), although it was told to read on rather than ask; or
        // "you can check Environment Canada for detailed hourly forecasts"
        // with no figure (round 4).
        final offered = AnswerCleanup.offersToLookFurther(said);
        toldToRead = true;
        t.clearAnswer();
        if (said.isNotEmpty) thinking.write('\n$said\n');
        toolMessages.addAll([
          {'role': 'assistant', 'content': said},
          {
            'role': 'user',
            'content': unchecked
                ? 'Search first: that figure changes, so look it up now '
                      'and answer my question from what you find.'
                : dated
                ? 'Today is ${DateTime.now().toIso8601String().substring(0, 10)}. '
                      'Give the age as of today, worked out from the birth '
                      'date in the sources.'
                : offered
                ? 'Yes. Read the best source now and answer my question '
                      'from what it says.'
                : 'Read the best page now with read_url and answer my '
                      'question with the figures it gives.',
          },
        ]);
        t.newParser();
        continue;
      }
      if (calls.isEmpty) {
        if (rounds == 0 && prompt.researchTurn) t.researchSkipped = true;
        // A stray block the model wrote without stopping is not shown.
        if (said != roundText.trim()) t.replaceAnswer(said);
        break;
      }
      if (rounds >= settings.toolMaxRounds) {
        lastRound = true;
        t.clearAnswer();
        toolMessages.add({
          'role': 'user',
          'content':
              '(No more tool calls are available. Answer my question now from the tool results above, citing their source numbers.)',
        });
        t.newParser();
        continue;
      }
      rounds++;
      t.clearAnswer();
      if (said.isNotEmpty) thinking.write('\n$said\n');
      toolMessages.add({
        'role': 'assistant',
        // Native turns carry their calls structurally; repeating the markup
        // in the text made the template render every call twice.
        'content': nativeTools ? said : roundText,
        if (nativeTools)
          'tool_calls': [
            for (final c in calls)
              {...c.toJson(), 'arguments': c.jsonArguments},
          ],
      });
      var repeated = false;
      for (final call in calls) {
        if (_cancelled) break;
        // The same phone action again (Qwen3.5 0.8B prepared one timer four
        // times, 2026-10-08): not prepared twice; the model answers. On the
        // phone any second one of the same kind counts: after a five-minute
        // timer the 0.8B prepared two "0 minute" timers (Conversation probe
        // round 7, 2026-10-18).
        if (PhoneActions.kinds.contains(call.name) &&
            runner.trace.any(
              (r) =>
                  r.ok &&
                  r.call.name == call.name &&
                  (local ||
                      PhoneAction(r.call.name, r.call.args).detail ==
                          PhoneAction(call.name, call.args).detail),
            )) {
          repeated = true;
          toolMessages.add({
            'role': 'tool',
            'tool_call_id': call.id,
            'name': call.name,
            'content':
                'Already prepared: the card is shown under your answer. '
                'Do not prepare it again; answer the user now.',
          });
          continue;
        }
        t.lease.transition(TurnStage.tools);
        budget?.useTool();
        state = state.copyWith(
          notice: _t.noticeUsingTool(call.name, _argSummary(call)),
        );
        final result = await runner.run(call);
        thinking.write(
          '\n▸ ${call.name}${_argSummary(call)} → ${result.ok ? '' : 'error: '}'
          '${result.output.length > 160 ? '${result.output.substring(0, 160)}…' : result.output}\n',
        );
        toolMessages.add({
          'role': 'tool',
          'tool_call_id': call.id,
          'name': call.name,
          'content': result.output,
        });
      }
      if (repeated) lastRound = true;
      t.stage('tools${rounds}Ms');
      // Pages the tools read become this answer's sources, numbered as the
      // tool results numbered them (the runner was seeded with the evidence
      // already in the prompt).
      t.sources = List.of(runner.sources);
      for (final s in runner.sponsored) {
        if (!t.sponsored.any((x) => x.url == s.url)) t.sponsored.add(s);
      }
      t.newParser();
    }
  }

  /// A follow-up answered from pages read earlier that say they lack the
  /// answer: searches the web once and answers again from what it finds.
  /// "And how many shots does its battery last?" kept the Z30's Wikipedia
  /// page, which has no battery figure, and Qwen3.5 0.8B said so twice
  /// (app quality probe, 2026-10-20). Nothing found: the first answer stays.
  Future<void> _searchAfterRecall(
    _Turn t,
    _Asked asked,
    _Planned planned,
  ) async {
    if (!t.searchIfLacking ||
        t.failure != null ||
        _cancelled ||
        !_alive ||
        t.echoStopped ||
        t.resume != null) {
      return;
    }
    t.parser?.close();
    final said = t.answer.toString().trim();
    if (said.length > 400 ||
        !(AnswerCleanup.deniesFigure(said, t.input) ||
            ClaimCheck.saysSourcesLack(said))) {
      return;
    }
    final plan = RetrievalPlan.of(
      planned.contextual,
      webEnabled: true,
      always: true,
    );
    if (plan.mode != RetrievalMode.search) return;
    final recalled = t.sources, sponsored = t.sponsored;
    void restore() {
      t.sources = recalled;
      t.sponsored = sponsored;
      t.replaceAnswer(said);
    }

    t.searchIfLacking = false;
    t.clearAnswer();
    t.thinking.write(
      '\n(The pages read earlier lack the answer; searched the web.)\n',
    );
    t.sources = [];
    t.sponsored = [];
    final searched = (
      plan: plan,
      contextual: planned.contextual,
      previousQuestion: planned.previousQuestion,
      selfQuestion: false,
      recalledTurn: false,
      followUpSearch: true,
    );
    final found = await _lookUp(t, asked, searched);
    if (found == null || t.sources.isEmpty || _cancelled || !_alive) {
      if (_alive) restore();
      return;
    }
    final prompt = await _assemblePrompt(t, asked.user, searched, found);
    if (prompt == null || _cancelled || !_alive) {
      if (_alive) restore();
      return;
    }
    t.newParser();
    await _runRounds(t, prompt);
  }

  /// The turn's last step, however it ended: the answer cleaned, checked
  /// and saved, then memory, the title and the closing notice.
  Future<void> _endTurn(_Turn t) async {
    t.deadline?.cancel();
    _retrievalCancel?.cancel('Turn ended');
    t.lease.transition(TurnStage.saving);
    try {
      t.repaint?.cancel();
      t.checkpoint?.cancel();
      t.parser?.close();
      await t.answerSub?.cancel();
      await t.thinkSub?.cancel();
      await t.pendingWrite;
      t.lease.transition(
        t.failure != null
            ? TurnStage.failed
            : _cancelled
            ? TurnStage.stopped
            : TurnStage.complete,
      );
      if (_alive) {
        _cleanAnswer(t);
        await _checkAnswer(t);
        final grounding = _groundingNotice(t);
        // A check that found something to doubt rides with the answer: the
        // triangle under it opens the whole warning (tester, 2026-10-19).
        final warning =
            grounding != null &&
                t.sources.isNotEmpty &&
                grounding != _t.noticeCitationsMatched
            ? grounding
            : null;
        await _saveAnswer(t, warning: warning);
        final learned = await _learnAndName(t);
        _showTurnEnd(t, grounding: grounding, learned: learned);
      }
    } finally {
      _turns.release(t.lease);
      if (_alive) {
        ref.read(sessionBusyProvider.notifier).state = false;
        if (state.isGenerating) {
          state = state.copyWith(isGenerating: false, isLoadingModel: false);
        }
      }
    }
  }

  /// The answer as it is saved: a restated answer once, without stray
  /// closing tags or lines narrating the request; a spoken one cut to
  /// length; the app's own answers in place of the model's.
  void _cleanAnswer(_Turn t) {
    final ok = t.failure == null && !_cancelled;
    var cleaned = AnswerCleanup.dropAskedBack(
      AnswerCleanup.dropNarration(
        AnswerCleanup.dropRepeats(ToolMarkup.stripOrphans(t.answer.toString())),
        sentences: t.spoken || t.sources.isNotEmpty,
      ),
      t.input,
    );
    final most = ref.read(settingsProvider).spokenSentences;
    if (t.spoken && most > 0) {
      cleaned = AnswerCleanup.spokenLength(cleaned, max: most);
    }
    if (cleaned.length < t.answer.length) t.replaceAnswer(cleaned);
    final aboutUser = t.aboutUser;
    if (aboutUser != null && ok) {
      final own = AboutUser.ownFacts(t.answer.toString(), aboutUser);
      if (own != t.answer.toString()) t.replaceAnswer(own);
    }
    // A spoken sum or name is said as the app knows it, and nothing else.
    final appAnswer = t.appAnswer;
    if (appAnswer != null && ok) t.replaceAnswer(appAnswer);
    // Nothing was read: a citation number points at nothing. The phone's
    // model too: Qwen3.5 0.8B copied "[1]" from the turn before into an
    // answer with no sources (Conversation probe, 2026-10-20).
    if (t.sources.isEmpty) {
      final plain = AnswerCleanup.dropCitations(t.answer.toString());
      if (plain.length < t.answer.length) t.replaceAnswer(plain);
    }
    // An attached file or photo is the source: no closing note that live
    // data is unavailable. Qwen3.5 0.8B added one to a figure it read from
    // a spreadsheet (media probe, 2026-10-21).
    if (t.attachments.isNotEmpty && ok) {
      final kept = AnswerCleanup.dropLiveNote(t.answer.toString());
      if (kept.length < t.answer.length) t.replaceAnswer(kept);
    }
    // Copied twice: say so rather than show the prompt as an answer.
    if (t.echoStopped) t.replaceAnswer(_t.echoedAnswer);
    // Gemma 4 E2B often says nothing after preparing an action (phone probe
    // 2026-10-07): the card alone, under an empty bubble. A spoken phone
    // answer that describes the card's steps says the app's line instead:
    // the 0.8B told the user "you've tapped Yes to confirm" before anything
    // was tapped (Conversation probe round 7, 2026-10-18). A remote model
    // too: LM Studio Gemma 4 E4B said "I have set a timer… You can tap on
    // that notification to start it!" while the card still waited (round
    // 9).
    if (ok &&
        (t.answer.toString().trim().isEmpty ||
            (t.spoken && AnswerChecks.actionTalk(t.answer.toString()))) &&
        (t.runner?.trace.any(
              (r) => r.ok && PhoneActions.kinds.contains(r.call.name),
            ) ??
            false)) {
      t.replaceAnswer(_t.actionReadyAnswer);
    }
  }

  /// An answer from sources: its citations matched by wording and
  /// figures, its sentences checked against the pages, and a changing
  /// figure dated by its newest source.
  Future<void> _checkAnswer(_Turn t) async {
    if (t.failure != null || _cancelled || t.echoStopped) return;
    final sources = t.sources;
    if (sources.isNotEmpty &&
        !AnswerChecks.refusal.hasMatch(t.answer.toString())) {
      // A partly cited answer gets its uncited sentences matched too
      // (tester, 2026-10-07: "missing [n] citations are added").
      final hadCitations = CitationMatch.hasCitations(t.answer.toString());
      String? cited;
      try {
        cited = CitationMatch.attach(
          t.answer.toString(),
          t.sourceTexts(),
          fill: true,
        );
      } catch (_) {
        // Best effort: a page the matcher cannot read (D1 benchmark,
        // 2026-10-11) leaves the answer as written, never loses it.
      }
      if (cited != null && cited != t.answer.toString()) {
        t.matchedCitations = !hadCitations;
        t.replaceAnswer(cited);
      }
      // Every sentence against the sources: words, names, years and (with
      // the embedding model) meaning. Not for a spoken answer: its figures
      // are words ("four hundred ninety-nine dollars") that the sources'
      // digits never back (remote Conversation probe, 2026-10-18), and
      // Conversation shows no notice.
      if (ref.read(settingsProvider).figureCheck && !t.spoken) {
        t.claims = await ClaimCheckRunner.run(
          t.answer.toString(),
          sources,
          embedder: _webEmbedder(),
          judge: _supportJudge(),
        );
      }
    }
    // A changing figure says how recent its pages are (tester, 2026-10-19:
    // no refusal, but the date the sources were updated). A forecast is
    // not a figure: "the sources do not say when they were last updated"
    // under tomorrow's weather read oddly (remote sweep, 2026-10-21).
    final answer = t.answer.toString();
    if (!_cancelled &&
        t.appAnswer == null &&
        !t.newsAnswer &&
        !InstantAnswers.isWeather(t.askedInContext) &&
        RetrievalPlan.timeSensitive(t.askedInContext) &&
        !AnswerChecks.refusal.hasMatch(answer) &&
        !SourceDates.dated(answer)) {
      final cited = SourceDates.cited(answer, sources);
      if (cited.isNotEmpty) {
        final newest = SourceDates.newest(cited);
        final line = newest == null
            ? _t.answerSourcesUndated
            : _t.answerSourcesDated(SourceDates.format(newest, _t.localeName));
        t.answer.write('\n\n$line');
      }
    }
  }

  /// What the notice says about the answer's grounding: matched
  /// citations, a figure or claim the sources do not back, or why an
  /// answer that refused had no sources.
  String? _groundingNotice(_Turn t) {
    if (t.failure != null || _cancelled) return null;
    final answer = t.answer.toString();
    final sources = t.sources;
    final figureCheck = ref.read(settingsProvider).figureCheck;
    String? doubted() => figureCheck
        ? AnswerChecks.figureNotice(answer, sources, _t) ??
              ClaimCheckRunner.notice(t.claims, _t)
        : null;
    if (sources.isNotEmpty) {
      if (t.spoken) return null;
      if (t.matchedCitations) return doubted() ?? _t.noticeCitationsMatched;
      return AnswerChecks.groundingNotice(answer, sources.length, _t) ??
          doubted();
    }
    if (!AnswerChecks.refusal.hasMatch(answer)) return null;
    if (ref.read(settingsProvider).webMode == WebMode.off) {
      return _t.noticeNoSourcesWebOff;
    }
    return state.notice?.isNotEmpty == true
        ? state.notice
        : _t.noticeNoSourcesNoSearch;
  }

  /// Saves the answer over its placeholder row with the record of what
  /// produced it (CHAT-04), or removes the placeholder when nothing came.
  Future<void> _saveAnswer(_Turn t, {String? warning}) async {
    final db = t.db;
    final chatId = t.chatId;
    final resume = t.resume;
    if (!t.accepted ||
        chatId == null ||
        (t.answer.isEmpty && t.thinking.isEmpty)) {
      if (t.placeholderSaved) {
        // Nothing was generated: an empty interrupted row would only confuse.
        try {
          await db.deleteMessage(t.assistantId);
        } catch (_) {}
      }
      if (t.accepted && !_cancelled && t.failure == null) {
        t.failure = _t.chatErrorNoText;
      }
      return;
    }
    final answer = t.answer.toString();
    final thinking = t.thinking.toString().trim();
    final model = t.model, settings = t.settings;
    final runner = t.runner;
    final budget = t.budget;
    final failed = t.failure != null;
    final msg = ChatMessage(
      id: t.assistantId,
      role: ChatRole.assistant,
      content: answer,
      reasoning: thinking.isEmpty ? null : thinking,
      timestamp: resume?.timestamp ?? DateTime.now(),
      modelId: t.modelId,
      tokenCount: t.metrics?['tokens'] as int?,
      status: t.compareWith != null
          ? failed
                ? 'alternative:error'
                : _cancelled
                ? 'alternative:stopped'
                : 'alternative'
          : failed
          ? 'error'
          : _cancelled
          ? 'stopped'
          : 'complete',
      sourcesJson:
          resume?.sourcesJson ?? jsonEncode(_sourceMaps(t.displayedSources())),
      parentId: t.answerParent,
      // CHAT-04: what produced this answer, for fair comparisons and bug
      // reports. A resumed answer keeps its first run's record.
      runJson:
          resume?.runJson ??
          (model != null && settings != null
              ? TurnRun.capture(
                  settings: settings,
                  preset: ref.read(presetsProvider).active,
                  model: model,
                  metrics: {
                    ...?t.metrics,
                    'lifecycle': t.lease.trace,
                    'contextAudit': t.contextAudit(_fittedOmitted),
                    'memoryUsed': [
                      ...t.usedMemoryNotes
                          .split('\n')
                          .where((s) => s.startsWith('- ')),
                      if (runner != null)
                        for (final result in runner.trace)
                          if (result.call.name == 'recall' && result.ok)
                            ...result.output
                                .split('\n')
                                .where((s) => s.startsWith('- ')),
                    ],
                    if (budget != null) 'operationTokens': budget.usedTokens,
                    'warning': ?warning,
                    if (t.claims.isNotEmpty)
                      'claimCheck': {
                        'sentences': t.claims.length,
                        'flagged': [
                          for (final v in t.claims)
                            if (v.status != ClaimStatus.supported) v.toJson(),
                        ],
                      },
                    'evidenceAudit': EvidenceAudit.check(
                      answer,
                      t.sourceTexts(),
                    ).toJson(),
                  },
                  sources: t.sources.length,
                  origins: t.resolved?.origin ?? const {},
                  toolTrace: runner == null
                      ? const []
                      : [for (final r in runner.trace) r.toJson()],
                ).encode()
              : null),
    );
    try {
      await db.transaction(() async {
        // insertOnConflictUpdate: replaces the placeholder, or creates the
        // row if the placeholder write itself failed.
        await db.insertMessage(
          MessagesCompanion.insert(
            id: msg.id,
            chatId: chatId,
            role: 'assistant',
            content: msg.content,
            reasoning: drift.Value(msg.reasoning),
            timestamp: msg.timestamp,
            sequence: t.sequence + 1,
            status: drift.Value(msg.status),
            sourcesJson: drift.Value(msg.sourcesJson),
            modelId: drift.Value(t.modelId),
            tokenCount: drift.Value(msg.tokenCount),
            parentId: drift.Value(msg.parentId),
            runJson: drift.Value(msg.runJson),
          ),
        );
        await (db.update(db.chats)..where((c) => c.id.equals(chatId))).write(
          ChatsCompanion(updatedAt: drift.Value(DateTime.now())),
        );
      });
    } catch (e) {
      t.failure = _t.chatErrorSave('$e');
    }
    state = state.copyWith(messages: [...state.messages, msg]);
  }

  /// Memory and the chat's title after a completed, fresh exchange.
  /// Returns the notes to show as learned.
  ///
  /// Memory: on the phone it runs while the turn still counts as busy, so
  /// the engine is not shared; a remote connection gets its own client and
  /// learns in the background, so the turn ends when the answer does (a
  /// second hosted request per message made remote chats feel slow). A
  /// remote model's notes wait for the title, so both go in one request.
  ///
  /// The model names a new chat after its first exchange (report
  /// 2026-10-04: "the model should name the chat"), unless the user has
  /// renamed it already. Local: while the turn is still busy, a few
  /// tokens; remote: in the background on its own client. A spoken turn
  /// leaves both for [nameChatLater], once the voice is quiet.
  Future<List<Memory>> _learnAndName(_Turn t) async {
    var learned = state.learned;
    final model = t.model, settings = t.settings;
    if (model == null || settings == null) return learned;
    final input = t.input, said = t.answer.toString();
    final chatId = t.chatId, messageId = t.sourceMessageId;
    final facts = t.memoryFacts;
    final fresh =
        t.failure == null &&
        !_cancelled &&
        t.insertUser &&
        t.resume == null &&
        t.learn &&
        said.isNotEmpty &&
        !state.temporary;
    _MemoryJob? remoteNotes;
    if (fresh &&
        UserMemory.worthExtracting(input) &&
        ref.read(settingsProvider).memoryEnabled) {
      final remainingFacts = UserMemory.maxFactsPerTurn - learned.length;
      final needsExtraction =
          remainingFacts > 0 && UserMemory.needsModelExtraction(input);
      final modelLearningAllowed =
          !settings.usesRemote ||
          (settings.activeRemoteProfile?.shareMemory == true &&
              settings.activeRemoteProfile?.learnMemory == true);
      if (modelLearningAllowed && needsExtraction && settings.usesRemote) {
        remoteNotes = (
          existing: facts,
          remainingFacts: remainingFacts,
          sourceMessageId: messageId,
        );
      } else if (modelLearningAllowed && needsExtraction && _spoken) {
        final localEngine = t.localEngine;
        _memoryLater = (keep) async {
          if (!keep()) return;
          final extracted = await _learn(
            localEngine,
            model,
            settings,
            existing: facts,
            userMessage: input,
            answer: said,
            remainingFacts: remainingFacts,
            chatId: chatId,
            sourceMessageId: messageId,
          );
          if (extracted != null &&
              extracted.isNotEmpty &&
              _alive &&
              state.chatId == chatId) {
            state = state.copyWith(learned: [...state.learned, ...extracted]);
          }
        };
      } else if (modelLearningAllowed && needsExtraction) {
        state = state.copyWith(notice: _t.noticeUpdatingMemory);
        final extracted = await _learn(
          t.engine,
          model,
          settings,
          existing: facts,
          userMessage: input,
          answer: said,
          remainingFacts: remainingFacts,
          chatId: chatId,
          sourceMessageId: messageId,
        );
        learned = [...learned, ...?extracted];
      }
    }
    final wantsTitle =
        fresh &&
        t.promptOverride == null &&
        input.isNotEmpty &&
        settings.autoTitles &&
        chatId != null &&
        state.messages.where((m) => m.role == ChatRole.user).length == 1;
    if (settings.usesRemote && (wantsTitle || remoteNotes != null)) {
      unawaited(
        _afterRemoteTurn(
          model,
          settings,
          chatId: chatId,
          question: input,
          answer: said,
          attachments: t.attachments,
          title: wantsTitle,
          memory: remoteNotes,
        ),
      );
    } else if (wantsTitle) {
      if (_spoken) {
        final localEngine = t.localEngine;
        _titleLater = (keep) => _nameChat(
          localEngine,
          model,
          settings,
          chatId: chatId,
          question: input,
          answer: said,
          keep: keep,
        );
      } else {
        state = state.copyWith(notice: _t.noticeNamingChat);
        await _nameChat(
          t.engine,
          model,
          settings,
          chatId: chatId,
          question: input,
          answer: said,
          attachments: t.attachments,
        );
      }
    }
    return learned;
  }

  /// The turn's end on screen: generation off, the metrics, and the one
  /// notice that matters most (stopped, an output limit, grounding,
  /// trimmed context, throttling, the photo or battery notes).
  void _showTurnEnd(
    _Turn t, {
    required String? grounding,
    required List<Memory> learned,
  }) {
    final ok = t.failure == null && !_cancelled;
    final settings = t.settings;
    final budget = t.budget;
    final saverReason = t.saverReason;
    final answer = t.answer.toString();
    final trimmed = t.metrics?['trimmedMessages'] as int? ?? 0;
    final finish = t.metrics?['finishReason'] as String? ?? '';
    String? outputNote;
    if (ok) {
      if (finish == 'length') {
        outputNote = _t.noticeTokenLimit(settings?.maxTokens ?? 0);
      } else if (finish == 'stop') {
        outputNote = _t.noticeStopSequence;
      }
      if (t.researchSkipped && answer.isNotEmpty) {
        outputNote = _t.noticeResearchSkipped;
      }
      if (settings != null && settings.structuredOutput && answer.isNotEmpty) {
        final problem = AnswerChecks.structuredOutputProblem(
          answer,
          settings,
          truncated: finish == 'length',
          t: _t,
        );
        if (problem != null) outputNote = problem;
      }
    }
    final imageNote = t.attachments.any((a) => a.isImage) && !t.vision
        ? (ref.read(settingsProvider).usesRemote ? null : state.notice)
        : null;
    // A remote server's speed says nothing about the phone's heat (remote
    // probe, 2026-10-18: "Speed dropped 48%" on LM Studio).
    final throttle = ok && t.engine is! RemoteEngine
        ? _throttleNotice(t.engine.metrics)
        : null;
    state = state.copyWith(
      isGenerating: false,
      isLoadingModel: false,
      clearReasoning: true,
      partialAnswer: '',
      error: t.failure,
      metrics: {
        ...?t.metrics,
        'lifecycle': t.lease.trace,
        'build': BuildIdentity.toJson(),
        'contextAudit': t.contextAudit(_fittedOmitted),
        if (budget != null) 'operationTokens': budget.usedTokens,
        'evidenceAudit': EvidenceAudit.check(answer, t.sourceTexts()).toJson(),
        'stages': {...t.stages, 'generateMs': t.stageClock.elapsedMilliseconds},
        'batterySaver': ?saverReason,
        'queries': ?t.searchQueries,
        if (t.searchQueries != null)
          'searchProviders': [
            ref.read(duckDuckGoScraperProvider).health.toJson(),
          ],
      },
      clearNotice:
          !_cancelled &&
          trimmed == 0 &&
          throttle == null &&
          grounding == null &&
          imageNote == null &&
          saverReason == null &&
          outputNote == null,
      learned: learned,
      notice: _cancelled
          ? _t.noticeStopped
          : outputNote ??
                grounding ??
                (trimmed > 0
                    ? _t.noticeTrimmed(trimmed)
                    : throttle ??
                          imageNote ??
                          (saverReason == null
                              ? null
                              : BatterySaver.notice(saverReason, _t))),
    );
  }

  /// Stores the question (and the chat, the first time) and returns the
  /// chat id, the question and the answer's sequence slot minus one.
  Future<({String chatId, ChatMessage user, int sequence})> _saveQuestion(
    String input, {
    required List<Attachment> attachments,
    required bool insertUser,
    String? parentId,
    ChatMessage? resume,
    String? modelId,
  }) async {
    final db = _database;
    final id = state.chatId ?? const Uuid().v4();
    final now = DateTime.now();
    // Ancestry: a new question continues the last live turn; a
    // re-asked question (edit) is a sibling of the one it replaces.
    final user = !insertUser && _lastLiveUser != null
        ? _lastLiveUser!
        : ChatMessage(
            id: const Uuid().v4(),
            role: ChatRole.user,
            content: input,
            timestamp: now,
            attachments: attachments,
            parentId: parentId ?? state.messages.where(isLive).lastOrNull?.id,
          );
    // The assistant row takes sequence + 1: after a new question, after
    // the existing last row, or (resuming) its own original slot.
    final storedRows = await db.getMessages(id);
    final lastSequence = storedRows.fold(
      -1,
      (n, r) => r.sequence > n ? r.sequence : n,
    );
    final sequence = resume != null
        ? (await db.getMessages(
                id,
              )).firstWhere((r) => r.id == resume.id).sequence -
              1
        : insertUser
        ? lastSequence + 1
        : lastSequence;
    if (insertUser) {
      await db.transaction(() async {
        if (await db.getChat(id) == null) {
          await db.upsertChat(
            ChatsCompanion.insert(
              id: id,
              title: ChatTitles.defaultTitle(input, attachments),
              modelId: drift.Value(modelId),
              createdAt: now,
              updatedAt: now,
              overridesJson: drift.Value(
                jsonEncode(ref.read(chatOverridesProvider)),
              ),
            ),
          );
        }
        await db.insertMessage(
          MessagesCompanion.insert(
            id: user.id,
            chatId: id,
            role: 'user',
            content: input,
            timestamp: now,
            sequence: sequence,
            attachmentsJson: drift.Value(
              jsonEncode([for (final a in attachments) a.toJson()]),
            ),
            parentId: drift.Value(user.parentId),
          ),
        );
        await (db.update(db.chats)..where((t) => t.id.equals(id))).write(
          ChatsCompanion(updatedAt: drift.Value(now)),
        );
      });
      if (!state.temporary && _projectId != null) {
        try {
          await ref.read(conversationWorkspaceProvider.notifier).assign([
            id,
          ], _projectId);
        } catch (e) {
          // A metadata failure must not hide the already committed question.
          if (_alive) state = state.copyWith(notice: '$e');
        }
      }
      state = state.copyWith(chatId: id, messages: [...state.messages, user]);
    }
    return (chatId: id, user: user, sequence: sequence);
  }

  /// The part of the system prompt every path of a turn shares: the app's
  /// default, the preset, the user's instructions and a caller's extra
  /// (Goals). Also the memory notes that follow it, [notes] for an ordinary
  /// turn and [researchNotes] for one that researches (pinned notes and how
  /// to answer only), and every note, for learning after the answer.
  Future<
    ({String system, String notes, String researchNotes, List<String> facts})
  >
  _baseSystem(
    String input, {
    required InferenceSettings settings,
    required Preset preset,
    String? extraSystem,
  }) async {
    var facts = const <String>[];
    var notes = '';
    var researchNotes = '';
    final baseSystem = StringBuffer(
      _spoken
          ? AppConstants.spokenSystemPrompt
          : AppConstants.defaultSystemPrompt,
    );
    if (preset.systemPrompt.isNotEmpty) {
      baseSystem.write('\n${preset.systemPrompt}');
    }
    final project = ref
        .read(conversationWorkspaceProvider)
        .projects
        .where((p) => p.id == _projectId)
        .firstOrNull;
    if (project != null && project.instructions.isNotEmpty) {
      baseSystem.write('\nProject instructions:\n${project.instructions}');
    }
    baseSystem.write('\n${settings.systemPrompt}');
    if (extraSystem != null && extraSystem.trim().isNotEmpty) {
      baseSystem.write('\n${extraSystem.trim()}');
    }
    // A French or Spanish question gets its answer in that language, with
    // or without sources (tester, 2026-10-19).
    final asked = WikipediaClient.languageFor(input, 'en');
    if (asked != 'en') {
      final language = asked == 'fr' ? 'French' : 'Spanish';
      baseSystem.write('\nThe user writes in $language: answer in $language.');
    }
    if (settings.memoryEnabled &&
        (!settings.usesRemote ||
            settings.activeRemoteProfile?.shareMemory == true)) {
      final memories = (await ref.read(memoryStoreProvider).all())
          .where(
            (m) => m.expiresAt == null || m.expiresAt!.isAfter(DateTime.now()),
          )
          .toList();
      final consent = ref.read(settingsProvider);
      if (!_alive ||
          !consent.memoryEnabled ||
          (settings.usesRemote &&
              consent.remoteProfiles
                      .where((p) => p.id == settings.activeRemoteProfile?.id)
                      .firstOrNull
                      ?.shareMemory !=
                  true)) {
        return (
          system: baseSystem.toString(),
          notes: '',
          researchNotes: '',
          facts: const <String>[],
        );
      }
      facts = [for (final m in memories) m.content];
      // A greeting is not steered by notes: with them, a small model opens
      // with "how is your visit to X going?" a week later (report).
      if (!RetrievalPlan.smallTalk(input) || memories.any((m) => m.pinned)) {
        final pinned = {
          for (var i = 0; i < memories.length; i++)
            if (memories[i].pinned) i,
        };
        String block(List<int> selected) => UserMemory.promptBlock(
          [for (final i in selected) memories[i].content],
          notedAt: [for (final i in selected) memories[i].updatedAt],
        );
        notes = block(
          UserMemory.relevant(
            input,
            facts,
            pinned: pinned,
            byWords: !_canRecall(settings) && !RetrievalPlan.smallTalk(input),
          ),
        );
        researchNotes = block(
          UserMemory.relevant(input, facts, pinned: pinned, byWords: false),
        );
      }
    }
    return (
      system: baseSystem.toString(),
      notes: notes,
      researchNotes: researchNotes,
      facts: facts,
    );
  }

  /// The typed tools this turn offers (those enabled whose host gate is
  /// open), and their instructions added to [system]: the text protocol
  /// when the template cannot carry tools, the tool policy, and the
  /// research steps of a model-driven research turn.
  ({ToolRunner? runner, List<ToolSpec> tools, bool native, bool clock})
  _offerTools(
    String input, {
    required InferenceSettings settings,
    required TextEngine engine,
    required StringBuffer system,
    required List<SearchResult> sources,
    required bool researchTurn,
    bool remoteBrain = false,
    required bool continuing,
    bool allowRecall = true,
  }) {
    ToolRunner? offered;
    // Typed tools (roadmap P2): offered only when enabled and only those
    // whose host gate is open. A template that cannot carry tool
    // definitions gets the plain-text protocol instead.
    List<ToolSpec> tools = const [];
    var nativeTools = false;
    var clock = false;
    // A greeting or one-word message gets no tools at all: offered a
    // search tool, small models call it on "hi" (report 2026-09-20).
    // On the phone, neither does a message with nothing to look up or work
    // out: the descriptions cost about 700 tokens before the first word
    // (review 2026-09-28). A chat that had tools keeps them.
    final chat = state.chatId;
    final phoneActions =
        PhoneActions.wanted(input) ||
        remoteBrain ||
        (chat != null && _actionChats.contains(chat));
    // After an action, retaining the native schema keeps the conversation's
    // system prefix reusable. Small talk uses toolChoice=none and ignores
    // any unsolicited call; it still gets an ordinary spoken answer.
    final keepActionPrefix =
        !settings.usesRemote &&
        engine.metrics['supportsTools'] == true &&
        chat != null &&
        _actionChats.contains(chat);
    final mayNeed =
        researchTurn ||
        phoneActions ||
        (_canRecall(settings) && UserMemory.personalQuery(input)) ||
        settings.usesRemote ||
        settings.toolChoice == ToolChoice.required ||
        (chat != null && _toolChats.contains(chat)) ||
        RetrievalPlan.mayNeedTools(
          input,
          documents:
              settings.toolDocuments && settings.knowledgeCollection.isNotEmpty,
        );
    // Phone actions only prepare a card the user confirms, so they are
    // offered for an action request even with the other tools off.
    if ((settings.toolsEnabled || phoneActions) &&
        !continuing &&
        !settings.structuredOutput &&
        (!RetrievalPlan.smallTalk(input) || keepActionPrefix) &&
        mayNeed) {
      final runner = ToolRunner(
        scraper: ref.read(duckDuckGoScraperProvider),
        reader: ref.read(webPageReaderProvider),
        knowledge: ref.read(knowledgeStoreProvider),
        settings: settings,
        cancel: _retrievalCancel,
        remote: settings.usesRemote,
        researchRecipe: researchTurn ? ResearchRecipe.forQuestion(input) : null,
        newsDesk: ref.read(newsDeskProvider),
        recall: _canRecall(settings) && !researchTurn && allowRecall
            ? (query) => _recallMemory(query, settings)
            : null,
        phoneActions: phoneActions,
        actionsOnly: !settings.toolsEnabled,
      );
      offered = runner;
      tools = runner.specs();
      // Evidence is already in the prompt: offering the web tools too
      // invites a needless extra round (each one a full request).
      if (sources.isNotEmpty && !researchTurn && !remoteBrain) {
        tools = [
          for (final t in tools)
            if (!const {
              'search_web',
              'search_news',
              'read_url',
              'find_in_page',
            }.contains(t.name))
              t,
        ];
      }
      if (tools.isNotEmpty && chat != null) _toolChats.add(chat);
      if (phoneActions && !remoteBrain && chat != null) _actionChats.add(chat);
      nativeTools =
          tools.isNotEmpty &&
          (settings.usesRemote || engine.metrics['supportsTools'] == true);
      // "Tomorrow at 9" needs today's date and the local time. On the
      // phone it goes with the request (the caller adds it): a system
      // prompt that changes every minute made each turn of a chat with
      // phone actions read the whole conversation again.
      if (tools.any((t) => PhoneActions.kinds.contains(t.name)) ||
          remoteBrain) {
        if (settings.usesRemote) {
          system.write('\n${TurnPrompts.clockLine()}');
        } else {
          clock = true;
        }
      }
      if (tools.isNotEmpty) {
        system.write(
          TurnPrompts.toolSystemText(
            tools,
            native: nativeTools,
            required:
                researchTurn || settings.toolChoice == ToolChoice.required,
            research: researchTurn || remoteBrain,
          ),
        );
      }
      if (remoteBrain && tools.any((t) => t.name == 'search_web')) {
        system.write('\n${TurnPrompts.remoteBrainText}');
      }
      if (researchTurn && tools.any((t) => t.name == 'search_web')) {
        system.write(
          NewsIntent.of(input) != null &&
                  tools.any((t) => t.name == 'search_news')
              ? '\nResearch before answering: call search_news for the latest stories, read one or two of the most relevant with read_url if details are needed, then answer from them with [n] citations.'
              : '\nResearch before answering: call search_web with a focused query of a few keywords, read the most promising result with read_url (or find_in_page for one detail), search again with different words if the first results do not answer, then answer from what you read with [n] citations. Say so when the pages do not settle the question.',
        );
        system.write(
          '\nResearch recipe: ${ResearchRecipe.forQuestion(input).instructions}',
        );
      }
    }
    return (runner: offered, tools: tools, native: nativeTools, clock: clock);
  }

  /// How long a chat waits for the device server to finish a request.
  static Duration hostedWait = const Duration(minutes: 3);

  /// While "Use this device as a server" runs, the phone's chats use the
  /// served model: another model would unload it under the client (a
  /// clear error instead), and a request in progress is waited for rather
  /// than raced. False when the user stopped the wait.
  Future<bool> _shareWithHosting(ModelInfo model) async {
    var hosting = ref.read(deviceHostingProvider);
    if (!hosting.running) return true;
    if (hosting.modelId != null && hosting.modelId != model.id) {
      throw StateError(_t.chatErrorServing(hosting.modelId!));
    }
    final clock = Stopwatch()..start();
    while (hosting.running && hosting.activeClient != null) {
      if (_cancelled || !_alive) return false;
      if (clock.elapsed > hostedWait) {
        throw StateError(_t.chatErrorServerBusy('${hosting.activeClient}'));
      }
      state = state.copyWith(
        notice: _t.noticeWaitingServer('${hosting.activeClient}'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 250));
      hosting = ref.read(deviceHostingProvider);
    }
    return true;
  }

  /// Writes the title (and memory) a spoken turn left for later ([send]'s
  /// `spoken`), now that the answer has been heard. A new turn stops it; it is tried again
  /// on the next call.
  Future<void> nameChatLater() async {
    if (_memoryLater != null &&
        _naming == null &&
        !state.isGenerating &&
        !ref.read(modelManagerProvider).isLoadingModel) {
      final memory = _memoryLater!;
      _memoryLater = null;
      _namingStopped = false;
      final learning = memory(() => !_namingStopped);
      _naming = learning;
      try {
        await learning;
      } catch (_) {
        // Memory is best effort.
      } finally {
        _naming = null;
      }
      // Stopped by a new turn: tried again after it.
      if (_namingStopped) _memoryLater ??= memory;
    }
    final run = _titleLater;
    if (run == null ||
        _naming != null ||
        state.isGenerating ||
        ref.read(modelManagerProvider).isLoadingModel) {
      return;
    }
    _namingStopped = false;
    final naming = run(() => !_namingStopped);
    _naming = naming;
    try {
      await naming;
    } finally {
      _naming = null;
    }
    if (!_namingStopped && identical(_titleLater, run)) _titleLater = null;
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
  }) async {
    var cuts = 0;
    var rounds = 0;
    while (rounds++ < 12) {
      final budget = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: model.family.fallbackTemplate,
        settings: settings,
        assistantPrefix: '',
        tools: tools,
      );
      if (budget['fits'] == true || _cancelled) break;
      Map<String, Object>? biggest;
      for (final m in toolMessages) {
        if (m['role'] != 'tool') continue;
        if (biggest == null ||
            (m['content'] as String).length >
                (biggest['content'] as String).length) {
          biggest = m;
        }
      }
      // Older turns first, then long results, then the last exchanges
      // (see [ContextUse.omitOldestExchange]).
      final longResult =
          biggest != null && (biggest['content'] as String).length >= 4000;
      var omitted = ContextUse.omitOldestExchange(messages, keep: 2);
      if (omitted == 0 && !longResult) {
        omitted = ContextUse.omitOldestExchange(messages);
      }
      if (omitted > 0) {
        _fittedOmitted += omitted;
        rounds--;
        continue;
      }
      if (biggest == null) break;
      final text = biggest['content'] as String;
      if (text.length < 1000) break;
      final kept = text.substring(0, text.length ~/ 2);
      final at = messages.indexOf(biggest);
      final shortened = {
        ...biggest,
        'content': '$kept\n[… cut to fit the context …]',
      };
      toolMessages[toolMessages.indexOf(biggest)] = shortened;
      if (at >= 0) messages[at] = shortened;
      cuts++;
    }
    return cuts == 0 ? null : _t.noticeToolCut(cuts);
  }

  /// Shortens attached document text in the last user turn until the prompt
  /// fits (halving the largest file each round, keeping its beginning).
  /// Returns a notice when something was cut.
  Future<String?> fitDocuments(
    TextEngine engine,
    List<Map<String, Object>> messages,
    InferenceSettings settings,
    ModelInfo model,
  ) async {
    final last = messages.last;
    if (last['role'] != 'user' ||
        !(last['content'] as String).contains('[File: ')) {
      return null;
    }
    final original = last['content'] as String;
    var content = original;
    var rounds = 0;
    while (rounds++ < 12) {
      final budget = await engine.previewPrompt(
        messages: messages,
        fallbackTemplate: model.family.fallbackTemplate,
        settings: settings,
        assistantPrefix: '',
      );
      if (budget['fits'] == true || _cancelled) break;
      final blocks = RegExp(
        r'\[File: ([^\]]+)\]\n([\s\S]*?)\n\[End of file: \1\]',
      ).allMatches(content).toList();
      final biggest = blocks.isEmpty
          ? null
          : blocks.reduce(
              (a, b) => b.group(2)!.length > a.group(2)!.length ? b : a,
            );
      // Older turns first, then the long file, then the last exchange
      // (see [ContextUse.omitOldestExchange]).
      var omitted = ContextUse.omitOldestExchange(messages, keep: 1);
      if (omitted == 0 &&
          (biggest == null || biggest.group(2)!.length < 8000)) {
        omitted = ContextUse.omitOldestExchange(messages);
      }
      if (omitted > 0) {
        _fittedOmitted += omitted;
        rounds--;
        continue;
      }
      // Largest file block first.
      if (biggest == null) break;
      final text = biggest.group(2)!;
      if (text.length < 2000) break;
      final kept = text.substring(0, text.length ~/ 2);
      content = content.replaceRange(
        biggest.start,
        biggest.end,
        '[File: ${biggest.group(1)}]\n$kept\n[… cut to fit the context …]\n[End of file: ${biggest.group(1)}]',
      );
      messages.last = {...last, 'content': content};
    }
    if (content == original) return null;
    final before = original.length, after = content.length;
    return _t.noticeDocCut((after * 100 / before).round());
  }

  static String _argSummary(ToolCall call) {
    final a = call.args;
    final v = a['query'] ?? a['url'] ?? a['expression'];
    if (v == null) return '';
    final text = '$v';
    return ' (${text.length > 48 ? '${text.substring(0, 45)}…' : text})';
  }

  static const storedExcerptChars = 12000;

  List<Map<String, Object>> _sourceMaps(List<SearchResult> sources) {
    final out = <Map<String, Object>>[];
    var evidenceNumber = 0;
    for (final source in sources) {
      if (!source.sponsored) evidenceNumber++;
      out.add({
        if (!source.sponsored) 'number': evidenceNumber,
        'title': source.title,
        'url': source.url,
        'snippet': source.snippet,
        'coverage': source.coverage,
        if (source.archiveDate != null) 'archiveDate': source.archiveDate!,
        if (source.archiveId != null) 'archiveId': source.archiveId!,
        if (source.archiveLanguage != null)
          'archiveLanguage': source.archiveLanguage!,
        'retrievalStatus': source.sponsored
            ? 'sponsored_not_used'
            : source.newsItem
            ? 'news_story'
            : source.pageText == null
            ? 'snippet_only'
            : 'page_read',
        if (source.sponsored) 'sponsored': true,
        // Pages a tool read keep their whole text in memory; the stored copy
        // is bounded (large TEXT reads from SQLite are implicated in the
        // release heap corruption).
        if (source.pageText != null)
          'excerpt': source.pageText!.length <= storedExcerptChars
              ? source.pageText!
              : '${source.pageText!.substring(0, storedExcerptChars)}…',
        if (source.finalUrl != null) 'finalUrl': source.finalUrl!,
        if (source.fetchedAt != null)
          'fetchedAt': source.fetchedAt!.toIso8601String(),
        if (source.publishedAt != null)
          'publishedAt': source.publishedAt!.toIso8601String(),
        if (source.updatedAt != null)
          'updatedAt': source.updatedAt!.toIso8601String(),
        if (source.stale) 'stale': true,
        if (source.readError != null) 'readError': source.readError!,
        if (source.outlet != null) 'outlet': source.outlet!,
        if (source.newsItem) 'newsItem': true,
        if (source.remembered) 'remembered': true,
      });
    }
    return out;
  }

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
