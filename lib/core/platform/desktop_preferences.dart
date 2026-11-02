import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_host.dart';

class DesktopPreferences {
  final bool advanced, leanPrompt, sidebarCollapsed;
  const DesktopPreferences({
    this.advanced = false,
    this.leanPrompt = true,
    this.sidebarCollapsed = false,
  });
}

final desktopPreferencesProvider =
    NotifierProvider<DesktopPreferencesNotifier, DesktopPreferences>(
      DesktopPreferencesNotifier.new,
    );

class DesktopPreferencesNotifier extends Notifier<DesktopPreferences> {
  late Future<void> ready;
  bool _alive = true;
  Future<void> _writes = Future.value();

  @override
  DesktopPreferences build() {
    ref.onDispose(() => _alive = false);
    ready = Future.microtask(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!_alive) return;
      state = DesktopPreferences(
        advanced: prefs.getBool('desktop_advanced') ?? false,
        sidebarCollapsed: prefs.getBool('desktop_sidebar_collapsed') ?? false,
        leanPrompt: prefs.getBool('desktop_lean_prompt') ?? true,
      );
      DesktopHost.leanPrompt = state.leanPrompt;
    });
    return const DesktopPreferences();
  }

  Future<void> set({
    bool? advanced,
    bool? leanPrompt,
    bool? sidebarCollapsed,
  }) async {
    await ready;
    if (!_alive) return;
    state = DesktopPreferences(
      advanced: advanced ?? state.advanced,
      sidebarCollapsed: sidebarCollapsed ?? state.sidebarCollapsed,
      leanPrompt: leanPrompt ?? state.leanPrompt,
    );
    DesktopHost.leanPrompt = state.leanPrompt;
    final next = state;
    _writes = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('desktop_advanced', next.advanced);
      await prefs.setBool('desktop_sidebar_collapsed', next.sidebarCollapsed);
      await prefs.setBool('desktop_lean_prompt', next.leanPrompt);
    });
    await _writes;
  }
}
