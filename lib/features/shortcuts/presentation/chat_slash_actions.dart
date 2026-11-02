import '../../../inference/engine/diffusiongemma_engine.dart';
import '../../models/domain/entities/model_info.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_dialog.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/island/status_island.dart';
import '../../../core/providers/shared_providers.dart';
import '../../../inference/engine/text_engine.dart';
import '../../chat/domain/context_summary.dart';
import '../../chat/domain/entities/chat_message.dart';
import '../../chat/presentation/providers/chat_provider.dart';
import '../../models/presentation/providers/model_manager_provider.dart';
import '../../models/presentation/widgets/model_picker_sheet.dart';
import '../../settings/presentation/providers/effective_settings_provider.dart';
import '../../settings/domain/entities/inference_settings.dart';
import '../../tools/presentation/tools_quick_panel.dart';
import '../domain/context_compactor.dart';
import '../domain/prompt_shortcut.dart';
import 'slash_command_composer.dart';

bool isChatAction(String text) =>
    chatActionCommands.contains(
      text.trim().split(RegExp(r'\s+')).first.replaceFirst(RegExp(r'^/'), ''),
    ) &&
    text.trimLeft().startsWith('/');

(PromptShortcut, String)? expandChatShortcut(
  String text,
  List<PromptShortcut> shortcuts, {
  required List<ChatMessage> messages,
  String lang = 'en',
}) {
  final expanded = PromptShortcut.apply(text, shortcuts, lang: lang);
  if (expanded == null) return null;
  final name = expanded.$1.name;
  final words = text.trim().split(RegExp(r'\s+'));
  if ((const ['summarize', 'explain'].contains(name) && words.length == 1) ||
      name == 'translate' && words.length <= 2) {
    final live = messages.where(ChatNotifier.isLive).toList();
    final source = name == 'summarize'
        ? live.map((m) => '${m.role.name}: ${m.content}').join('\n\n')
        : live.where((m) => m.role == ChatRole.assistant).lastOrNull?.content ??
              '';
    if (source.isNotEmpty) return (expanded.$1, '${expanded.$2}\n\n$source');
  }
  return expanded;
}

Future<void> runChatAction(
  BuildContext context,
  WidgetRef ref,
  String text, {
  required Future<void> Function() export,
}) async {
  final command = text.trim().split(RegExp(r'\s+')).first.substring(1);
  if (ref.read(chatProvider).isGenerating || ref.read(sessionBusyProvider)) {
    return;
  }
  final t = context.l10n;
  try {
    switch (command) {
      case 'clear':
        ref.read(chatProvider.notifier).newChat();
      case 'model':
        await showModelPickerSheet(context);
      case 'tools':
        await showAppDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(t.slashTools),
            content: const SizedBox(
              width: 560,
              child: SingleChildScrollView(child: ToolsQuickPanel()),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: Text(t.desktopClose),
              ),
            ],
          ),
        );
      case 'export':
        await export();
      case 'retry':
        await ref.read(chatProvider.notifier).regenerate();
      case 'system':
        final settings = ref.read(effectiveSettingsProvider).effective;
        final value = await promptText(
          context,
          title: t.settingLabelSystemPrompt,
          initial: settings.systemPrompt,
          confirmLabel: t.save,
          minLines: 4,
          maxLines: 12,
          allowEmpty: true,
        );
        if (value != null && context.mounted) {
          await ref.read(chatProvider.notifier).setChatOverrides({
            ...ref.read(chatOverridesProvider),
            'systemPrompt': value,
          });
        }
      case 'think':
        final settings = ref.read(effectiveSettingsProvider).effective;
        final next = settings.thinkingModeEnabled
            ? ThinkingLevel.off
            : ThinkingLevel.medium;
        await ref.read(chatProvider.notifier).setChatOverrides({
          ...ref.read(chatOverridesProvider),
          ...next.overrides,
        });
        if (context.mounted) {
          showIslandToast(
            context,
            next == ThinkingLevel.off ? t.thinkOffToast : t.slashThink,
          );
        }
      case 'compact':
        await _compact(context, ref);
    }
  } catch (e) {
    if (context.mounted) showIslandToast(context, '$e', tone: IslandTone.error);
  }
}

Future<void> _compact(BuildContext context, WidgetRef ref) async {
  final t = context.l10n;
  final chat = ref.read(chatProvider);
  final settings = ref.read(effectiveSettingsProvider).effective;
  final model = ref.read(modelManagerProvider).loadedModel;
  final live = chat.messages.where(ChatNotifier.isLive).toList();
  final source = live.take((live.length - 4).clamp(0, live.length)).toList();
  while (source.isNotEmpty && source.last.role != ChatRole.assistant) {
    source.removeLast();
  }
  if (chat.chatId == null ||
      chat.temporary ||
      source.isEmpty ||
      !settings.usesRemote && model == null) {
    showIslandToast(context, t.slashCompactUnavailable);
    return;
  }
  final TextEngine engine = settings.usesRemote
      ? ref.read(remoteEngineProvider)
      : model?.id == diffusionGemmaModelId
      ? ref.read(diffusionGemmaEngineProvider)
      : ref.read(llamaEngineProvider);
  final editor = TextEditingController();
  ref.read(sessionBusyProvider.notifier).state = true;
  final future = const ContextCompactor().summarize(
    engine: engine,
    settings: settings,
    source: source.map((m) => '${m.role.name}: ${m.content}').join('\n\n'),
    instruction: t.slashCompactInstruction,
    fallbackTemplate: model?.family.fallbackTemplate ?? '',
    fitError: t.slashCompactFit,
  );
  var populated = false;
  try {
    final approved = await showAppDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => FutureBuilder<String>(
        future: future,
        builder: (dialog, snapshot) {
          if (snapshot.hasData && !populated) {
            editor.text = snapshot.data!;
            populated = true;
          }
          return AlertDialog(
            title: Text(t.contextSummary),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: snapshot.hasData
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(t.slashCompactSaved),
                          TextField(
                            controller: editor,
                            minLines: 4,
                            maxLines: 12,
                            maxLength: 6000,
                          ),
                        ],
                      )
                    : snapshot.hasError
                    ? Text('${snapshot.error}')
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const LinearProgressIndicator(),
                          Text(t.slashCompactBusy),
                        ],
                      ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (!snapshot.hasData) engine.cancel();
                  Navigator.pop(dialog);
                },
                child: Text(t.cancel),
              ),
              if (snapshot.hasData)
                FilledButton(
                  onPressed: () => Navigator.pop(dialog, editor.text),
                  child: Text(t.save),
                ),
            ],
          );
        },
      ),
    );
    if (approved != null && approved.trim().isNotEmpty && context.mounted) {
      final current = ref.read(chatProvider);
      if (current.chatId != chat.chatId ||
          ContextSummary.hash(
                current.messages.where(ChatNotifier.isLive).take(source.length),
              ) !=
              ContextSummary.hash(source)) {
        return;
      }
      await ContextSummary.save(chat.chatId!, approved, source);
      if (context.mounted) {
        showIslandToast(context, t.slashCompactSaved, tone: IslandTone.done);
      }
    }
  } finally {
    await future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    ref.read(sessionBusyProvider.notifier).state = false;
    // Dialog transition may still retain its editable text.
    WidgetsBinding.instance.addPostFrameCallback((_) => editor.dispose());
  }
}
