import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// What another app shared to OnDevice LLM: text (often a link), an
/// optional subject (a page title, an email subject) and files already
/// copied into the app's cache by the platform side.
class SharedPayload {
  final String text;
  final String subject;
  final List<({String name, String path})> files;

  /// Files the platform could not copy (empty, unreadable or over 64 MB),
  /// and whether more than the first eight were shared.
  final List<String> skipped;
  final bool more;
  final String? error;

  /// Set when a scheduled prompt's notification was tapped: 'chat' asks
  /// [text] in a new chat, 'goal' opens Goals with it.
  final String? scheduled;

  /// Text selected in another app ("Ask OnDevice LLM" in its selection
  /// menu): the user picks what to do with it.
  final bool selection;

  /// Opened from the assistant gesture, the quick-settings tile or the
  /// home-screen widget: 'voice' starts a voice conversation, 'chat' a new
  /// chat.
  final String? launch;
  const SharedPayload({
    this.text = '',
    this.subject = '',
    this.files = const [],
    this.skipped = const [],
    this.more = false,
    this.error,
    this.scheduled,
    this.selection = false,
    this.launch,
  });

  bool get isEmpty =>
      launch == null &&
      text.trim().isEmpty &&
      subject.trim().isEmpty &&
      files.isEmpty;

  factory SharedPayload.fromMap(Map<Object?, Object?> m) => SharedPayload(
    text: m['text'] as String? ?? '',
    subject: m['subject'] as String? ?? '',
    files: [
      for (final f in (m['files'] as List? ?? const []))
        if (f is Map && f['path'] is String)
          (name: f['name'] as String? ?? 'file', path: f['path'] as String),
    ],
    skipped: [
      for (final s in (m['skipped'] as List? ?? const []))
        if (s is String) s,
    ],
    more: m['more'] == true,
    error: m['error'] as String?,
    scheduled: m['scheduled'] as String?,
    selection: m['selection'] == true,
    launch: m['launch'] as String?,
  );

  /// The message the new chat starts with. A shared link alone gets the
  /// page's title in front when the other app sent one ("Title\nURL"), so
  /// the user sees what it is; the composer leaves it for them to finish.
  String get draft {
    final t = text.trim();
    final s = subject.trim();
    if (s.isEmpty || t.contains(s)) return t;
    if (t.isEmpty) return s;
    return '$s\n$t';
  }
}

/// The platform side of "Share to OnDevice LLM" (ShareInbox.kt). [take]
/// returns the pending share once; [arrivals] fires when a share reaches an
/// app that is already running.
class ShareInbox {
  static const _channel = MethodChannel('ondevice_llm/share');
  static final _arrivals = StreamController<void>.broadcast();
  static bool _listening = false;

  static Stream<void> get arrivals {
    if (!_listening && Platform.isAndroid) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'arrived') _arrivals.add(null);
      });
    }
    return _arrivals.stream;
  }

  /// Remove temporary native share copies after they have been imported.
  /// Imported attachments live in the attachment store, not these paths.
  static Future<void> discardFiles(SharedPayload payload) async {
    final parents = <String>{};
    for (final shared in payload.files) {
      final file = File(shared.path);
      parents.add(file.parent.path);
      try {
        if (await file.exists()) await file.delete();
      } on FileSystemException catch (_) {}
    }
    for (final path in parents) {
      try {
        await Directory(path).delete();
      } on FileSystemException catch (_) {}
    }
  }

  static Future<SharedPayload?> take() async {
    if (!Platform.isAndroid) return null;
    try {
      final m = await _channel.invokeMapMethod<Object?, Object?>('take');
      return m == null ? null : SharedPayload.fromMap(m);
    } on PlatformException catch (e) {
      return SharedPayload(error: e.message);
    } on MissingPluginException {
      return null;
    }
  }
}
