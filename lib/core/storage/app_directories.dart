import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../platform/desktop_host.dart';

/// Where the app keeps its own data (database, attachments, made files).
/// On a phone that is the app's private documents folder; on Windows
/// `getApplicationDocumentsDirectory` is the user's Documents folder, so the
/// app uses its per-user AppData folder there instead.
Future<Directory> appDataDirectory() => DesktopHost.active
    ? getApplicationSupportDirectory()
    : getApplicationDocumentsDirectory();
