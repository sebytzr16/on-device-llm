import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/app_design.dart';
import '../core/island/status_island.dart';
import '../core/l10n/l10n.dart';
import '../core/motion/motion.dart';
import '../core/platform/device_info.dart';
import '../features/chat/presentation/providers/chat_provider.dart';
import '../features/goals/presentation/goals_page.dart';
import 'projects_page.dart';
import '../features/settings/domain/entities/inference_settings.dart';
import '../features/settings/presentation/providers/settings_provider.dart';
import 'chat_pane.dart';
import '../core/platform/desktop_preferences.dart';
import 'launch_arguments.dart';
import 'keyboard_shortcuts.dart';
import 'chat_tools.dart';
import 'desktop_theme.dart';
import 'inspector_panel.dart';
import 'models_page.dart';
import 'compare_page.dart';
import 'server_page.dart';
import 'logs_page.dart';
import 'mcp/mcp_page.dart';
import 'mcp/mcp_registry.dart';
import 'image_gen_page.dart';
import 'settings_panel.dart';
import 'sidebar.dart';
import 'title_bar.dart';
import 'tray.dart';

/// What the main area shows. The sidebar and the shortcuts switch it.
enum DesktopSection {
  chat,
  projects,
  goals,
  models,
  imageGen,
  compare,
  server,
  logs,
  mcp,
  settings,
}

final desktopSectionProvider =
    NotifierProvider<DesktopSectionNotifier, DesktopSection>(
      DesktopSectionNotifier.new,
    );

class DesktopSectionNotifier extends Notifier<DesktopSection> {
  @override
  DesktopSection build() => DesktopSection.chat;
  void show(DesktopSection s) => state = s;
}

/// The Windows app: the same providers, database and engines as the phone,
/// with a window-shaped interface on top.
class DesktopApp extends ConsumerWidget {
  const DesktopApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeCode = ref.watch(settingsProvider.select((s) => s.localeCode));
    final themeChoice = ref.watch(
      settingsProvider.select((s) => s.themeChoice),
    );
    final accent = ref.watch(settingsProvider.select((s) => s.accent));
    final textScale = ref.watch(settingsProvider.select((s) => s.textScale));
    final motion = ref.watch(settingsProvider.select((s) => s.motion));
    return MaterialApp(
      title: 'OnDevice LLM',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: localeCode.isEmpty ? null : Locale(localeCode),
      theme: DesktopTheme.of(accent, dark: false),
      darkTheme: DesktopTheme.of(accent, dark: true),
      themeMode: switch (themeChoice) {
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.system => ThemeMode.system,
      },
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            MediaQuery.of(context).textScaler.scale(1) * textScale,
          ),
        ),
        child: MotionScope(
          choice: motion,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              // Shared pages report through the island; on the desktop it
              // drops in just under the title bar.
              MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  padding: const EdgeInsets.only(
                    top: DesktopTheme.titleBarHeight,
                  ),
                ),
                child: const StatusIsland(),
              ),
            ],
          ),
        ),
      ),
      home: const DesktopTrayHost(child: DesktopShell()),
    );
  }
}

class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key});

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  double _sidebarWidth = 272;
  bool _sidebarOpen = true;
  late final McpRegistry _mcp;
  final _searchFocus = FocusNode(debugLabel: 'chat search');
  final _composerFocus = FocusNode(debugLabel: 'composer');
  final _shellFocus = FocusNode(debugLabel: 'desktop shell');

  late final DesktopLaunchArguments _launchArguments;

  @override
  void initState() {
    super.initState();
    _mcp = ref.read(mcpRegistryProvider);
    _mcp.confirm = (server, call) {
      if (!mounted) return Future.value(McpConsent.deny);
      return confirmMcpCall(
        context,
        server,
        call.name,
        const JsonEncoder.withIndent('  ').convert(call.args),
      );
    };
    _launchArguments = DesktopLaunchArguments((path) async {
      _show(DesktopSection.models);
      await importDesktopModel(context, ref, path);
    }, onRefreshRateChanged: () => ref.invalidate(displayRefreshRateProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_launchArguments.start());
    });
    FocusManager.instance.addListener(_keepShortcutsLive);
  }

  /// When the focused widget leaves the screen (the composer after Ctrl+M,
  /// a closed menu), focus falls back to the route above the shell and key
  /// events no longer pass the shortcuts. Take it back; dialogs and menus
  /// have their own scopes and keep theirs.
  void _keepShortcutsLive() {
    final primary = FocusManager.instance.primaryFocus;
    if (primary == null || !_shellFocus.ancestors.contains(primary)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && FocusManager.instance.primaryFocus == primary) {
        _shellFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _mcp.confirm = null;
    _launchArguments.dispose();
    FocusManager.instance.removeListener(_keepShortcutsLive);
    _shellFocus.dispose();
    _searchFocus.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _show(DesktopSection s) =>
      ref.read(desktopSectionProvider.notifier).show(s);

  void _newChat() {
    ref.read(chatProvider.notifier).newChat();
    _show(DesktopSection.chat);
    _composerFocus.requestFocus();
  }

  List<DesktopShortcut> get _shortcuts {
    final t = context.l10n;
    return [
      DesktopShortcut(
        const SingleActivator(
          LogicalKeyboardKey.keyE,
          control: true,
          shift: true,
        ),
        t.desktopChatExport,
        () {
          exportDesktopChat(context, ref);
        },
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.keyN, control: true),
        t.newChat,
        _newChat,
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.keyK, control: true),
        t.desktopShortcutSearch,
        _focusSearch,
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.keyF, control: true),
        t.desktopShortcutSearch,
        _focusSearch,
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.keyL, control: true),
        t.desktopShortcutComposer,
        () {
          _show(DesktopSection.chat);
          _composerFocus.requestFocus();
        },
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.keyB, control: true),
        t.desktopToggleSidebar,
        () => setState(() => _sidebarOpen = !_sidebarOpen),
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.keyI, control: true),
        t.desktopInspectorToggle,
        () {
          _show(DesktopSection.chat);
          desktopInspectorOpen.value = !desktopInspectorOpen.value;
        },
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.keyM, control: true),
        t.models,
        () => _show(DesktopSection.models),
      ),
      DesktopShortcut(
        const SingleActivator(
          LogicalKeyboardKey.keyD,
          control: true,
          shift: true,
        ),
        t.desktopCompareTitle,
        () => _show(DesktopSection.compare),
      ),
      if (ref.watch(desktopPreferencesProvider).advanced)
        DesktopShortcut(
          const SingleActivator(
            LogicalKeyboardKey.keyL,
            control: true,
            shift: true,
          ),
          t.desktopLogsTitle,
          () => _show(DesktopSection.logs),
        ),
      DesktopShortcut(
        const SingleActivator(
          LogicalKeyboardKey.keyS,
          control: true,
          shift: true,
        ),
        t.desktopServerTitle,
        () => _show(DesktopSection.server),
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.comma, control: true),
        t.settings,
        () => _show(DesktopSection.settings),
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.escape),
        t.desktopShortcutStop,
        () {
          if (ref.read(chatProvider).isGenerating) {
            ref.read(chatProvider.notifier).cancel();
          }
        },
      ),
      DesktopShortcut(
        const SingleActivator(LogicalKeyboardKey.slash, control: true),
        t.desktopKeyboardShortcuts,
        _showShortcuts,
      ),
    ];
  }

  void _showShortcuts() => showDesktopShortcuts(context, _shortcuts);

  void _focusSearch() {
    if (!_sidebarOpen) setState(() => _sidebarOpen = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final advanced = ref.watch(desktopPreferencesProvider).advanced;
    final requested = ref.watch(desktopSectionProvider);
    final section =
        !advanced &&
            const {
              DesktopSection.logs,
              DesktopSection.mcp,
              DesktopSection.projects,
              DesktopSection.goals,
            }.contains(requested)
        ? DesktopSection.chat
        : requested;
    final c = context.colors;
    return CallbackShortcuts(
      bindings: {
        for (final shortcut in _shortcuts) shortcut.activator: shortcut.action,
      },
      child: Focus(
        focusNode: _shellFocus,
        autofocus: true,
        child: DesktopShortcutScope(
          shortcuts: _shortcuts,
          child: Scaffold(
            backgroundColor: c.ink,
            body: Column(
              children: [
                DesktopTitleBar(
                  onToggleSidebar: () =>
                      setState(() => _sidebarOpen = !_sidebarOpen),
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AnimatedContainer(
                        duration: context.motion.fade(DesktopTheme.medium),
                        curve: DesktopTheme.curve,
                        width: _sidebarOpen ? _sidebarWidth : 0,
                        child: ClipRect(
                          child: OverflowBox(
                            alignment: Alignment.centerLeft,
                            minWidth: _sidebarWidth,
                            maxWidth: _sidebarWidth,
                            child: ExcludeFocus(
                              excluding: !_sidebarOpen,
                              child: DesktopSidebar(
                                searchFocus: _searchFocus,
                                onNewChat: _newChat,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (_sidebarOpen)
                        _ResizeHandle(
                          onDrag: (dx) => setState(
                            () => _sidebarWidth = (_sidebarWidth + dx).clamp(
                              DesktopTheme.sidebarMin,
                              DesktopTheme.sidebarMax,
                            ),
                          ),
                        ),
                      Expanded(
                        child: _ContentPanel(
                          // The phone's crossfade: the old place blurs out
                          // as the new one sharpens in.
                          child: BlurSwitcher(
                            child: KeyedSubtree(
                              key: ValueKey(section),
                              child: switch (section) {
                                DesktopSection.chat => DesktopChatPane(
                                  composerFocus: _composerFocus,
                                ),
                                DesktopSection.models =>
                                  const DesktopModelsPage(),
                                DesktopSection.compare =>
                                  const DesktopComparePage(),
                                DesktopSection.server =>
                                  const DesktopServerPage(),
                                DesktopSection.logs => const DesktopLogsPage(),
                                DesktopSection.mcp => const DesktopMcpPage(),
                                DesktopSection.settings =>
                                  const DesktopSettingsPanel(),
                                DesktopSection.imageGen => _CreatePage(),
                                // Milestone 2 gives these their own desktop
                                // layouts; until then the shared pages sit in
                                // a reading-width column.
                                DesktopSection.goals => const _EmbeddedPage(
                                  child: GoalsPage(),
                                ),
                                DesktopSection.projects =>
                                  const DesktopProjectsPage(),
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The raised main area beside the sidebar, like a Windows 11 app's content
/// layer over Mica.
class _ContentPanel extends StatelessWidget {
  final Widget child;
  const _ContentPanel({required this.child});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: DesktopTheme.contentLayer(c),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDesign.rLg),
        ),
        border: Border(
          top: BorderSide(color: c.hairline),
          left: BorderSide(color: c.hairline),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDesign.rLg),
        ),
        child: child,
      ),
    );
  }
}

/// A shared phone page shown in the main area: its own navigator so the
/// pages it opens stay inside the panel, at a reading width. Its scaffold and
/// app bar take the panel's layer, and its title the desktop page heading, so
/// it reads as one of the window's pages rather than a phone screen.
class _EmbeddedPage extends StatelessWidget {
  final Widget child;
  const _EmbeddedPage({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: DesktopTheme.contentLayer(c),
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          toolbarHeight: 76,
          titleSpacing: 24,
          titleTextStyle: context.text.headline,
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: DesktopTheme.readingWidth,
          ),
          child: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  final ValueChanged<double> onDrag;
  const _ResizeHandle({required this.onDrag});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeColumn,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
      child: SizedBox(
        width: 5,
        child: Center(
          child: AnimatedContainer(
            duration: DesktopTheme.fast,
            width: 2,
            color: _hover
                ? context.colors.accent.fade(0.6)
                : Colors.transparent,
          ),
        ),
      ),
    ),
  );
}

class _CreatePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.desktopCreateTitle, style: context.text.headline),
            Text(
              context.l10n.desktopCreateExplanation,
              style: context.text.small,
            ),
          ],
        ),
      ),
      const Expanded(child: DesktopImageGenPage()),
    ],
  );
}
