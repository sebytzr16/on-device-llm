import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import '../core/design/app_design.dart';
import '../core/l10n/l10n.dart';
import '../core/logging/developer_logs.dart';
import '../core/motion/spring_entrance.dart';
import 'developer_widgets.dart';

class DesktopLogsPage extends ConsumerStatefulWidget {
  const DesktopLogsPage({super.key});
  @override
  ConsumerState<DesktopLogsPage> createState() => _DesktopLogsPageState();
}

class _DesktopLogsPageState extends ConsumerState<DesktopLogsPage> {
  final _scroll = ScrollController();
  String _query = '';
  int _level = 0;
  List<DeveloperLogEntry>? _paused;
  bool _scrollQueued = false;

  void _follow() {
    if (_scrollQueued) return;
    _scrollQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollQueued = false;
      if (!mounted || _paused != null || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.minScrollExtent);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final entries = ref.watch(developerLogsProvider);
    if (_paused == null) _follow();
    final shown = (_paused ?? entries).where((e) {
      final matches = switch (_level) {
        1 => e.level.value < Level.INFO.value,
        2 =>
          e.level.value >= Level.INFO.value &&
              e.level.value < Level.WARNING.value,
        3 =>
          e.level.value >= Level.WARNING.value &&
              e.level.value < Level.SEVERE.value,
        4 => e.level.value >= Level.SEVERE.value,
        _ => true,
      };
      return matches && '${e.tag} ${e.message}'.toLowerCase().contains(_query);
    }).toList();
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SpringEntrance(
            child: Text(t.desktopLogsTitle, style: context.text.headline),
          ),
          const SizedBox(height: 8),
          Text(t.desktopLogsHint, style: context.text.small),
          const SizedBox(height: 16),
          TextField(
            key: const Key('logs-filter'),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
            decoration: InputDecoration(
              labelText: t.desktopLogsFilter,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<int>(
                key: const Key('logs-level'),
                value: _level,
                items:
                    [
                          t.desktopLogsAll,
                          t.desktopLogsDebug,
                          t.desktopLogsInfo,
                          t.desktopLogsWarning,
                          t.desktopLogsError,
                        ].indexed
                        .map(
                          (e) =>
                              DropdownMenuItem(value: e.$1, child: Text(e.$2)),
                        )
                        .toList(),
                onChanged: (v) => setState(() => _level = v ?? 0),
              ),
              DeveloperButton(
                label: _paused == null
                    ? t.desktopLogsPause
                    : t.desktopLogsResume,
                onPressed: () => setState(
                  () => _paused = _paused == null ? List.of(entries) : null,
                ),
              ),
              DeveloperButton(
                label: t.desktopLogsClear,
                onPressed: () {
                  ref.read(developerLogsProvider.notifier).clear();
                  setState(() {
                    if (_paused != null) _paused = const [];
                  });
                },
              ),
              DeveloperButton(
                label: t.desktopLogsCopyAll,
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: shown.join('\n'))),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: context.colors.surfaceRaised,
                borderRadius: AppDesign.radius(AppDesign.rLg),
                border: Border.all(color: context.colors.hairline),
              ),
              child: shown.isEmpty
                  ? Center(
                      child: Text(t.desktopLogsEmpty, style: context.text.mono),
                    )
                  : Scrollbar(
                      controller: _scroll,
                      child: ListView.builder(
                        controller: _scroll,
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: shown.length,
                        itemBuilder: (context, index) {
                          final e = shown[shown.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: SelectableText(
                              '$e',
                              style: context.text.mono.copyWith(
                                color: e.level.value >= Level.SEVERE.value
                                    ? context.colors.danger
                                    : e.level.value >= Level.WARNING.value
                                    ? context.colors.accent
                                    : context.colors.text,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
