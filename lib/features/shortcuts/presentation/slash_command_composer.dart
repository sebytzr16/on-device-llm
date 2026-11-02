import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_design.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/platform/desktop_host.dart';
import '../prompt_shortcuts_provider.dart';
import 'shortcuts_page.dart';

const chatActionCommands = [
  'compact',
  'clear',
  'model',
  'tools',
  'export',
  'retry',
  'system',
  'think',
];
String slashDescription(AppLocalizations t, String command) =>
    switch (command) {
      'compact' => t.slashCompact,
      'clear' => t.slashClear,
      'model' => t.slashModel,
      'tools' => t.slashTools,
      'export' => t.slashExport,
      'retry' => t.slashRetry,
      'system' => t.slashSystem,
      'think' => t.slashThink,
      'summarize' => t.slashSummarize,
      'translate' => t.slashTranslate,
      'explain' => t.slashExplain,
      _ => '',
    };

/// The same filtered palette and keyboard behavior in both composers.
class SlashCommandComposer extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final Widget child;
  final VoidCallback onSubmit;
  final bool enabled;
  const SlashCommandComposer({
    super.key,
    required this.controller,
    required this.child,
    required this.onSubmit,
    this.enabled = true,
  });
  @override
  ConsumerState<SlashCommandComposer> createState() =>
      SlashCommandComposerState();
}

class SlashCommandComposerState extends ConsumerState<SlashCommandComposer> {
  int _cursor = 0;
  String? _dismissed;
  String _last = '';
  final _scroll = ScrollController();
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(SlashCommandComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (widget.controller.text == _last) return;
    setState(() {
      _last = widget.controller.text;
      _cursor = 0;
      _dismissed = null;
    });
  }

  List<(String, String)> _matches() {
    if (!widget.enabled || _dismissed == widget.controller.text) return [];
    final query = RegExp(
      r'^/([a-z0-9-]*)$',
    ).firstMatch(widget.controller.text)?[1];
    if (query == null) return [];
    final t = context.l10n;
    final saved = ref.read(promptShortcutsProvider);
    final commands = <String, String>{
      for (final name in chatActionCommands) name: slashDescription(t, name),
      for (final item in saved)
        if (!chatActionCommands.contains(item.name))
          item.name: slashDescription(t, item.name).isEmpty
              ? item
                    .localized(Localizations.localeOf(context).languageCode)
                    .description
              : slashDescription(t, item.name),
    };
    return [
      for (final e in commands.entries)
        if (e.key.startsWith(query)) (e.key, e.value),
    ];
  }

  void _select(String name) {
    final action = chatActionCommands.contains(name);
    widget.controller.value = TextEditingValue(
      text: '/$name${action ? '' : ' '}',
      selection: TextSelection.collapsed(
        offset: name.length + (action ? 1 : 2),
      ),
    );
    if (action) widget.onSubmit();
  }

  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final matches = _matches();
    if (matches.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      setState(() => _dismissed = widget.controller.text);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowUp) {
      setState(
        () => _cursor =
            (_cursor + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
            matches.length,
      );
      return KeyEventResult.handled;
    }
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _select(matches[_cursor.clamp(0, matches.length - 1)].$1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(promptShortcutsProvider);
    final matches = _matches();
    return Focus(
      onKeyEvent: handleKey,
      skipTraversal: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Bubbles, as before the palette (owner 2026-11-01): one row to
          // swipe on the phone, all of them wrapped on the PC.
          if (matches.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppDesign.sm),
              child: _chips(context, matches),
            ),
          widget.child,
        ],
      ),
    );
  }

  Widget _chips(BuildContext context, List<(String, String)> matches) {
    final c = context.colors;
    final chips = <Widget>[
      for (final (i, (name, description)) in matches.indexed)
        Tooltip(
          message: description,
          child: ActionChip(
            key: Key('shortcut-$name'),
            visualDensity: VisualDensity.compact,
            shape: StadiumBorder(
              side: BorderSide(
                color: i == _cursor && DesktopHost.active
                    ? c.accent
                    : c.hairline,
              ),
            ),
            backgroundColor: c.surfaceRaised,
            label: Text('/$name'),
            labelStyle: context.text.mono.copyWith(color: c.accent),
            onPressed: () => _select(name),
          ),
        ),
      ActionChip(
        key: const Key('shortcut-manage'),
        visualDensity: VisualDensity.compact,
        shape: StadiumBorder(side: BorderSide(color: c.hairline)),
        backgroundColor: c.surfaceRaised,
        avatar: Icon(Icons.tune, size: 14, color: c.textMuted),
        label: Text(context.l10n.composerManageShortcuts),
        labelStyle: context.text.mono.copyWith(color: c.textMuted),
        onPressed: () => Navigator.of(
          context,
        ).push(MaterialPageRoute<void>(builder: (_) => const ShortcutsPage())),
      ),
    ];
    if (DesktopHost.active) {
      return Wrap(
        key: const Key('shortcut-suggestions'),
        spacing: AppDesign.sm,
        runSpacing: AppDesign.sm,
        children: chips,
      );
    }
    return SizedBox(
      height: 36,
      child: ListView.separated(
        key: const Key('shortcut-suggestions'),
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppDesign.sm),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}
