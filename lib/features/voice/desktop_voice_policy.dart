import 'package:flutter/foundation.dart';

import '../../core/platform/desktop_host.dart';

bool offlineVoiceReady({
  required bool enabled,
  required bool installed,
  TargetPlatform? platform,
  bool? desktop,
}) =>
    !kIsWeb &&
    ((platform ?? defaultTargetPlatform) == TargetPlatform.android ||
        (desktop ?? DesktopHost.active)) &&
    enabled &&
    installed;
