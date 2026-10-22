part of 'chat_screen.dart';

/// The chat menu's actions: compare with another model, share, export,
/// and create a document from the conversation.
extension _ChatScreenActions on _ChatScreenState {
  Future<void> _contextSummary() async {
    final chat = ref.read(chatProvider);
    if (chat.chatId == null || chat.temporary || chat.isGenerating) return;
    final live = chat.messages.where(ChatNotifier.isLive).toList();
    // Always leave at least the latest two exchanges available verbatim.
    final source = live.take((live.length - 4).clamp(0, live.length)).toList();
    while (source.isNotEmpty && source.last.role != ChatRole.assistant) {
      source.removeLast();
    }
    final previous = await ContextSummary.read(chat.chatId);
    if (!mounted) return;
    final controller = TextEditingController(
      text:
          previous != null &&
              previous.fingerprint == ContextSummary.hash(source)
          ? previous.text
          : '',
    );
    try {
      final save = await showAppDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(dialog.l10n.contextSummary),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: AppDesign.md,
              children: [
                Text(dialog.l10n.contextSummaryHint),
                Text('${source.length} ${dialog.l10n.contextMessages}'),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 12,
                  maxLength: 6000,
                ),
                ExpansionTile(
                  title: Text(dialog.l10n.sourceMessage),
                  children: [
                    for (final m in source)
                      ListTile(
                        title: Text(
                          m.content,
                          maxLines: 5,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: Text(dialog.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(dialog.l10n.save),
            ),
          ],
        ),
      );
      if (save == true && mounted) {
        if (source.isEmpty && controller.text.trim().isNotEmpty) {
          throw StateError(context.l10n.contextSummaryTooShort);
        }
        await ContextSummary.save(chat.chatId!, controller.text, source);
      }
    } catch (e) {
      if (mounted) showIslandToast(context, '$e', tone: IslandTone.error);
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      controller.dispose();
    }
  }

  Future<void> _deleteTurn(ChatMessage message, {required bool pair}) async {
    try {
      final notifier = ref.read(chatProvider.notifier);
      final deletion = await notifier.deleteTurn(message.id, pair: pair);
      if (!mounted || deletion == null) return;
      final toast = islandToastFor(context);
      final unavailable = context.l10n.undoUnavailable;
      toast(
        context.l10n.messageDeleted,
        icon: Icons.delete_outline,
        action: IslandAction(context.l10n.undo, () async {
          try {
            final ok = await notifier.undoDelete(deletion);
            if (!ok) toast(unavailable);
          } catch (e) {
            toast('$e', tone: IslandTone.error);
          }
        }),
      );
    } catch (e) {
      if (mounted) showIslandToast(context, '$e', tone: IslandTone.error);
    }
  }

  /// Pins a downloaded model to this chat, or removes the pin.
  Future<void> _pickPin() async {
    if (ref.read(chatProvider).temporary) return;
    final chatId = ref.read(chatProvider).chatId;
    if (chatId == null) return;
    final current = ref.read(chatModelPinsProvider)[chatId];
    final models = ref
        .read(modelManagerProvider)
        .catalog
        .where((m) => m.isDownloaded)
        .toList();
    final picked = await showMorphSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => AppSheet(
        title: sheet.l10n.chatPinModel,
        meta: sheet.l10n.chatPinHint,
        scrollable: false,
        children: [
          ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: models.length + 1,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppDesign.md),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ListTile(
                  key: const Key('pin-none'),
                  leading: Icon(
                    current == null
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(sheet.l10n.chatPinNone),
                  onTap: () => Navigator.pop(sheet, ''),
                );
              }
              final m = models[index - 1];
              return ListTile(
                key: Key('pin-${m.id}'),
                leading: Icon(
                  current == m.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(m.displayName),
                onTap: () => Navigator.pop(sheet, m.id),
              );
            },
          ),
        ],
      ),
    );
    if (picked == null) return;
    await ref
        .read(chatModelPinsProvider.notifier)
        .set(chatId, picked.isEmpty ? null : picked);
  }

  /// FX-04: pick another downloaded model and answer the same question.
  Future<void> _compare(ChatMessage answer) async {
    final models = ref.read(modelManagerProvider);
    final candidates = models.catalog
        .where((m) => m.isDownloaded && m.id != answer.modelId)
        .toList();
    final picked = await showMorphSheet<ModelInfo>(
      context: context,
      useSafeArea: true,
      builder: (context) => AppSheet(
        title: context.l10n.compareWithTitle,
        meta: context.l10n.compareHint,
        scrollable: false,
        children: [
          ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: candidates.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppDesign.md),
            itemBuilder: (context, index) {
              final m = candidates[index];
              return ListTile(
                key: Key('compare-${m.id}'),
                leading: const Icon(Icons.memory),
                title: Text(m.displayName),
                subtitle: Text(
                  '${m.quantization.name.toUpperCase()} · ${m.sizeLabel}',
                ),
                onTap: () => Navigator.pop(context, m),
              );
            },
          ),
        ],
      ),
    );
    if (picked != null && mounted) {
      await ref.read(chatProvider.notifier).compare(picked);
    }
  }

  /// Plain-text copy of the conversation handed to the system share sheet.
  Future<void> _shareText() async {
    try {
      final chat = ref.read(chatProvider);
      final models = ref.read(modelManagerProvider);
      final text = ref
          .read(chatProvider.notifier)
          .plainText(modelName: models.loadedModel?.displayName);
      final dir = await getTemporaryDirectory();
      final title = chat.messages.isEmpty
          ? 'conversation'
          : chat.messages.first.content
                .replaceAll(RegExp(r'[^\w\s-]'), '')
                .trim()
                .split(RegExp(r'\s+'))
                .take(6)
                .join('-')
                .toLowerCase();
      final file = File(
        p.join(dir.path, '${title.isEmpty ? 'conversation' : title}.txt'),
      );
      await file.writeAsString(text, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/plain')],
          subject: 'Conversation from OnDevice LLM',
        ),
      );
    } catch (e) {
      if (mounted) {
        showIslandToast(
          context,
          context.l10n.shareFailed('$e'),
          tone: IslandTone.error,
        );
      }
    }
  }

  /// Adds selected visible turns to a collection as a searchable document.
  Future<void> _saveToKnowledge() async {
    final chat = ref.read(chatProvider);
    final messages = chat.messages
        .where((m) => ChatNotifier.isLive(m) && m.role != ChatRole.system)
        .toList();
    if (messages.isEmpty) return;
    final store = ref.read(knowledgeStoreProvider);
    final collections = await store.collections();
    if (!mounted) return;
    final selected = {for (final message in messages) message.id};
    final defaultTitle = messages
        .where((m) => m.role == ChatRole.user)
        .firstOrNull
        ?.content
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    final titleController = TextEditingController(
      text: defaultTitle == null || defaultTitle.isEmpty
          ? context.l10n.knowledgeChatTitle
          : defaultTitle.length > 80
          ? defaultTitle.substring(0, 80)
          : defaultTitle,
    );
    final active = ref.read(settingsProvider).knowledgeCollection.trim();
    final collectionController = TextEditingController(
      text: active.isNotEmpty ? active : (collections.firstOrNull ?? ''),
    );
    final approved = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: Text(dialog.l10n.saveToKnowledge),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: AppDesign.md,
                children: [
                  Text(dialog.l10n.knowledgeSaveHint),
                  TextField(
                    key: const Key('knowledge-save-collection'),
                    controller: collectionController,
                    decoration: InputDecoration(
                      labelText: dialog.l10n.knowledgeCollectionName,
                    ),
                  ),
                  if (collections.isNotEmpty) ...[
                    const SizedBox(height: AppDesign.sm),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final collection in collections)
                          ActionChip(
                            label: Text(collection),
                            onPressed: () =>
                                collectionController.text = collection,
                          ),
                      ],
                    ),
                  ],
                  TextField(
                    key: const Key('knowledge-save-title'),
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: dialog.l10n.knowledgeDocumentTitle,
                    ),
                  ),
                  Text(dialog.l10n.knowledgeSelectMessages),
                  SizedBox(
                    height: 220,
                    child: ListView(
                      children: [
                        for (final message in messages)
                          CheckboxListTile(
                            key: Key('knowledge-message-${message.id}'),
                            dense: true,
                            value: selected.contains(message.id),
                            title: Text(
                              message.content.trim().isEmpty
                                  ? (message.role == ChatRole.user
                                        ? dialog.l10n.you
                                        : dialog.l10n.assistant)
                                  : message.content.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              message.role == ChatRole.user
                                  ? dialog.l10n.you
                                  : dialog.l10n.assistant,
                            ),
                            onChanged: (checked) => update(() {
                              if (checked == true) {
                                selected.add(message.id);
                              } else {
                                selected.remove(message.id);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: Text(dialog.l10n.cancel),
            ),
            FilledButton(
              key: const Key('knowledge-save-confirm'),
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: Text(dialog.l10n.commonSave),
            ),
          ],
        ),
      ),
    );
    final collection = collectionController.text.trim();
    final title = titleController.text.trim();
    // The dialog's fields stay mounted during its closing transition.
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        collectionController.dispose();
        titleController.dispose();
      }),
    );
    if (approved != true || !mounted) return;
    if (collection.isEmpty || title.isEmpty) {
      showIslandToast(
        context,
        context.l10n.knowledgeNameRequired,
        tone: IslandTone.warning,
      );
      return;
    }
    try {
      final document = ChatDocument.select(
        messages: messages,
        selectedIds: selected,
        title: title,
        chatId: chat.chatId,
      );
      await store.import(
        collection: collection,
        name: '$title.txt',
        bytes: Uint8List.fromList(utf8.encode(document.text)),
      );
      if (ref.read(modelManagerProvider).embeddingReady) {
        unawaited(
          ref.read(knowledgeIndexerProvider.notifier).index(collection),
        );
      }
      if (mounted) {
        showIslandToast(
          context,
          context.l10n.knowledgeSaved(collection),
          tone: IslandTone.done,
        );
      }
    } catch (error) {
      if (mounted) {
        showIslandToast(
          context,
          context.l10n.knowledgeSaveFailed('$error'),
          tone: IslandTone.error,
        );
      }
    }
  }

  Future<void> _export(bool markdown) async {
    try {
      final data = ref.read(chatProvider.notifier).export(markdown: markdown);
      await FilePicker.saveFile(
        dialogTitle: 'Export conversation',
        fileName: 'ondevice-chat.${markdown ? 'md' : 'json'}',
        bytes: Uint8List.fromList(utf8.encode(data)),
      );
    } catch (e) {
      if (mounted) {
        showIslandToast(
          context,
          context.l10n.exportFailed('$e'),
          tone: IslandTone.error,
        );
      }
    }
  }

  Future<void> _createDocument() async {
    var format = 'docx';
    var template = DocumentTemplate.transcript;
    var title = 'OnDevice LLM document';
    var answersOnly = false;
    var includeBranches = false;
    var includeReasoning = false;
    var chooseMessages = false;
    var redactTerms = '';
    final approved = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: Text(dialogContext.l10n.createDocument),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              spacing: AppDesign.md,
              children: [
                TextFormField(
                  initialValue: title,
                  decoration: InputDecoration(
                    labelText: context.l10n.uiChatScreenActionsTitle,
                  ),
                  onChanged: (value) => title = value,
                ),
                DropdownButtonFormField<DocumentTemplate>(
                  initialValue: template,
                  decoration: InputDecoration(
                    labelText: context.l10n.uiChatScreenActionsDocumentType,
                  ),
                  items: [
                    for (final choice in DocumentTemplate.values)
                      DropdownMenuItem(
                        value: choice,
                        child: Text(DocumentDraftService.label(choice)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) update(() => template = value);
                  },
                ),
                DropdownButtonFormField<String>(
                  initialValue: format,
                  decoration: InputDecoration(
                    labelText: dialogContext.l10n.documentFormat,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'docx',
                      child: Text(context.l10n.uiChatScreenActionsWordDocx),
                    ),
                    DropdownMenuItem(
                      value: 'pdf',
                      child: Text(context.l10n.uiChatScreenActionsPDF),
                    ),
                    DropdownMenuItem(
                      value: 'txt',
                      child: Text(context.l10n.uiChatScreenActionsPlainTextTxt),
                    ),
                    DropdownMenuItem(
                      value: 'md',
                      child: Text(context.l10n.uiChatScreenActionsMarkdownMd),
                    ),
                    DropdownMenuItem(
                      value: 'html',
                      child: Text(context.l10n.uiChatScreenActionsHTML),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) update(() => format = value);
                  },
                ),
                SpringSwitchTile(
                  title: Text(dialogContext.l10n.answersOnly),
                  value: answersOnly,
                  onChanged: (value) => update(() => answersOnly = value),
                ),
                SpringSwitchTile(
                  title: Text(dialogContext.l10n.includeBranches),
                  value: includeBranches,
                  onChanged: (value) => update(() => includeBranches = value),
                ),
                SpringSwitchTile(
                  title: Text(dialogContext.l10n.includeReasoning),
                  value: includeReasoning,
                  onChanged: (value) => update(() => includeReasoning = value),
                ),
                SpringSwitchTile(
                  title: Text(
                    context.l10n.uiChatScreenActionsSelectIndividualMessages,
                  ),
                  value: chooseMessages,
                  onChanged: (value) => update(() => chooseMessages = value),
                ),
                TextFormField(
                  decoration: InputDecoration(
                    labelText: context
                        .l10n
                        .uiChatScreenActionsRedactTermsCommaSeparated,
                  ),
                  onChanged: (value) => redactTerms = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(dialogContext.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(dialogContext.l10n.saveDocument),
            ),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;
    try {
      final chat = ref.read(chatProvider);
      Set<String>? selectedIds;
      if (chooseMessages) {
        final eligible = [
          for (final message in chat.messages)
            if ((includeBranches || ChatNotifier.isLive(message)) &&
                (!answersOnly || message.role == ChatRole.assistant))
              message,
        ];
        final selected = {for (final message in eligible) message.id};
        selectedIds = await showAppDialog<Set<String>>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (dialogContext, update) => AlertDialog(
              title: Text(context.l10n.uiChatScreenActionsChooseMessages),
              content: SizedBox(
                width: 500,
                height: MediaQuery.sizeOf(dialogContext).height * 0.6,
                child: ListView.builder(
                  itemCount: eligible.length,
                  itemBuilder: (_, index) {
                    final message = eligible[index];
                    return CheckboxListTile(
                      value: selected.contains(message.id),
                      title: Text(message.role.name),
                      subtitle: Text(
                        message.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onChanged: (checked) => update(() {
                        if (checked == true) {
                          selected.add(message.id);
                        } else {
                          selected.remove(message.id);
                        }
                      }),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(dialogContext.l10n.cancel),
                ),
                FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, selected),
                  child: Text(context.l10n.uiChatScreenActionsUseSelection),
                ),
              ],
            ),
          ),
        );
        if (selectedIds == null || !mounted) return;
      }
      var document = ChatDocument.select(
        title: title.trim().isEmpty ? 'OnDevice LLM document' : title.trim(),
        messages: chat.messages,
        chatId: chat.chatId,
        selectedIds: chooseMessages
            ? selectedIds
            : answersOnly
            ? {
                for (final message in chat.messages)
                  if (message.role == ChatRole.assistant) message.id,
              }
            : null,
        includeBranches: includeBranches,
        includeReasoning: includeReasoning,
      ).redacted(redactTerms.split(','));
      if (document.messages.isEmpty) {
        throw const FormatException('No messages match this selection.');
      }
      if (template != DocumentTemplate.transcript) {
        document = document.normalizedCitations();
        final settings = ref.read(settingsProvider);
        final model = ref.read(modelManagerProvider).loadedModel;
        if (!settings.usesRemote && model == null) {
          throw StateError('Load a model before drafting a document.');
        }
        final TextEngine engine = settings.usesRemote
            ? ref.read(remoteEngineProvider)
            : ref.read(llamaEngineProvider);
        final fallback = model?.family.fallbackTemplate ?? '';
        final draftStore = DocumentDraftStore(drafts: _drafts);
        final documentKey = chat.chatId ?? 'new';
        final revisions = await draftStore.read(documentKey, template.name);
        if (!mounted) return;
        var restore = revisions.isNotEmpty;
        if (restore) {
          final choice = await showAppDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: Text(context.l10n.documentDraftSaved),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog, false),
                  child: Text(context.l10n.regenerate),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, true),
                  child: Text(context.l10n.continueLabel),
                ),
              ],
            ),
          );
          if (choice == null || !mounted) return;
          restore = choice;
        }
        final draft = restore
            ? revisions.first.content
            : await DocumentDraftService.generate(
                engine: engine,
                settings: settings,
                source: document,
                template: template,
                fallbackTemplate: fallback,
              );
        await draftStore.save(documentKey, template.name, draft);
        if (!mounted) return;
        final editor = TextEditingController(text: draft);
        Timer? autosave;
        String? saveError;
        void saveRevision() {
          autosave?.cancel();
          autosave = Timer(const Duration(milliseconds: 750), () async {
            try {
              await draftStore.save(documentKey, template.name, editor.text);
              saveError = null;
            } catch (error) {
              saveError = '$error';
            }
          });
        }

        editor.addListener(saveRevision);
        final edited = await showAppDialog<String>(
          context: context,
          builder: (dialogContext) => DefaultTabController(
            length: 2,
            child: AlertDialog(
              title: Text(context.l10n.uiChatScreenActionsReviewDocument),
              content: SizedBox(
                width: 600,
                height: 360,
                child: Column(
                  spacing: AppDesign.md,
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: context.l10n.documentEdit),
                        Tab(text: context.l10n.documentPreview),
                      ],
                    ),
                    if (revisions.length > 1)
                      DropdownButton<int>(
                        hint: Text(context.l10n.documentVersions),
                        items: [
                          for (var i = 0; i < revisions.length; i++)
                            DropdownMenuItem(
                              value: i,
                              child: Text(
                                revisions[i].savedAt
                                    .toLocal()
                                    .toString()
                                    .substring(0, 16),
                              ),
                            ),
                        ],
                        onChanged: (i) {
                          if (i != null) editor.text = revisions[i].content;
                        },
                      ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          TextField(
                            controller: editor,
                            expands: true,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                          ),
                          ValueListenableBuilder<TextEditingValue>(
                            valueListenable: editor,
                            builder: (_, value, _) =>
                                Markdown(data: value.text, selectable: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(dialogContext.l10n.cancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, editor.text),
                  child: Text(dialogContext.l10n.saveDocument),
                ),
              ],
            ),
          ),
        );
        autosave?.cancel();
        editor.removeListener(saveRevision);
        await draftStore.save(documentKey, template.name, editor.text);
        editor.dispose();
        if (saveError != null) throw StateError(saveError!);
        if (edited == null || !mounted) return;
        document = ChatDocument(
          title: document.title,
          chatId: chat.chatId,
          messages: [
            ChatMessage(
              id: 'generated-document',
              role: ChatRole.assistant,
              content: edited,
              timestamp: DateTime.now(),
              sourcesJson: jsonEncode([
                for (final message in document.messages)
                  ...jsonDecode(message.sourcesJson) as List,
              ]),
            ),
          ],
        );
      }
      final dialogTitle = context.l10n.createDocument;
      final bytes = switch (format) {
        'pdf' => await document.pdf(),
        'docx' => document.docx,
        'html' => Uint8List.fromList(utf8.encode(document.html)),
        'md' => Uint8List.fromList(utf8.encode(document.markdown)),
        _ => Uint8List.fromList(utf8.encode(document.text)),
      };
      final baseName = document.title
          .replaceAll(RegExp(r'[^\p{L}\p{N} _-]', unicode: true), '')
          .trim()
          .replaceAll(RegExp(r'\s+'), '-');
      final safeName = baseName.isEmpty
          ? 'ondevice-document'
          : baseName.substring(0, baseName.length.clamp(0, 80));
      await FilePicker.saveFile(
        dialogTitle: dialogTitle,
        fileName: '$safeName.$format',
        bytes: bytes,
      );
    } catch (error) {
      if (mounted) {
        showIslandToast(
          context,
          context.l10n.exportFailed('$error'),
          tone: IslandTone.error,
        );
      }
    }
  }

  /// Every way to take a chat elsewhere, in one sheet (request
  /// 2026-10-04: the menu had five separate entries for them).
  Future<void> _exportSheet() async {
    final t = context.l10n;
    final choice = await showMorphSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => AppSheet(
        title: t.shareOrExport,
        children: [
          for (final (value, icon, label) in [
            ('share', Icons.ios_share, t.shareAsText),
            ('md', Icons.description_outlined, t.exportMarkdown),
            ('json', Icons.data_object, t.exportJson),
            ('document', Icons.file_present_outlined, t.createDocument),
            ('save-knowledge', Icons.library_add_outlined, t.saveToKnowledge),
          ])
            ListTile(
              key: Key('export-$value'),
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.pop(context, value),
            ),
        ],
      ),
    );
    if (choice != null && mounted) _onMenu(choice);
  }

  void _onMenu(String action) {
    switch (action) {
      case 'export':
        unawaited(_exportSheet());
      case 'context-summary':
        unawaited(_contextSummary());
      case 'temporary':
        ref.read(chatProvider.notifier).newChat(temporary: true);
        unawaited(_switchDraft(null));
        showIslandToast(context, context.l10n.temporaryChatHint);
      case 'workspace':
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const ConversationWorkspacePage(),
          ),
        );
      case 'document':
        unawaited(_createDocument());
      case 'goals':
        _openGoal();
      case 'md':
        unawaited(_export(true));
      case 'json':
        unawaited(_export(false));
      case 'share':
        unawaited(_shareText());
      case 'save-knowledge':
        unawaited(_saveToKnowledge());
      case 'models':
        Navigator.pushNamed(context, AppRoutes.models);
      case 'settings':
        Navigator.pushNamed(context, AppRoutes.settings);
      case 'chat-settings':
        Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const _ChatOverridesPage()),
        );
      case 'metrics':
        unawaited(showMetricsSheet(context));
      case 'pin-model':
        unawaited(_pickPin());
    }
  }
}
