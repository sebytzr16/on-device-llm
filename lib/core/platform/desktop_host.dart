/// Whether this process runs the Windows desktop app. `main` turns it on
/// before the window opens. Tests run on a desktop host but exercise the
/// phone's behaviour, so they leave it off.
abstract final class DesktopHost {
  static bool active = false;

  /// Restored with settings before a turn reads the synchronous prompt builder.
  static bool leanPrompt = true;
}
