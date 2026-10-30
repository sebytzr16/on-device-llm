import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop window chrome: frameless with the app's own title bar and a
/// sensible minimum size. (Mica was tried: behind the frameless Flutter view
/// it renders black, so the window keeps the app's own solid palette.)
abstract final class DesktopWindow {
  static const minimumSize = Size(960, 600);
  static const initialSize = Size(1280, 800);

  static Future<void> init() async {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      minimumSize: minimumSize,
      title: 'OnDevice LLM',
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
}
