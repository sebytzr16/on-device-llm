import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'entities/chat_message.dart';

/// A user-approved summary replaces only the exact source prefix it was made
/// from. Editing, deleting or switching a branch invalidates it automatically.
class ContextSummary {
  final String text, fingerprint;
  final List<String> messageIds;
  const ContextSummary(this.text, this.fingerprint, this.messageIds);
  static const key = 'context_summaries_v1';
  static Future<void> _pending = Future.value();
  static String hash(Iterable<ChatMessage> rows) => sha256
      .convert(
        utf8.encode(
          jsonEncode([
            for (final m in rows)
              {
                'id': m.id,
                'role': m.role.name,
                'content': m.content,
                'sources': m.sourcesJson,
                'attachments': m.attachments.map((a) => a.toJson()).toList(),
              },
          ]),
        ),
      )
      .toString();
  bool validFor(List<ChatMessage> live) =>
      messageIds.length < live.length &&
      live.take(messageIds.length).map((m) => m.id).join(',') ==
          messageIds.join(',') &&
      hash(live.take(messageIds.length)) == fingerprint;
  static Future<ContextSummary?> read(String? chatId) async {
    if (chatId == null) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final all = jsonDecode(prefs.getString(key) ?? '{}') as Map;
      final j = all[chatId];
      if (j is! Map ||
          j['text'] is! String ||
          j['hash'] is! String ||
          j['ids'] is! List) {
        return null;
      }
      final ids = (j['ids'] as List).whereType<String>().toList();
      if (ids.isEmpty || (j['text'] as String).length > 6000) return null;
      return ContextSummary(j['text'], j['hash'], ids);
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(
    String chatId,
    String text,
    List<ChatMessage> source,
  ) {
    final next = _pending.then((_) => _save(chatId, text, source));
    _pending = next.catchError((Object _) {});
    return next;
  }

  static Future<void> _save(
    String chatId,
    String text,
    List<ChatMessage> source,
  ) async {
    if (text.length > 6000) {
      throw const FormatException('Summary exceeds 6,000 characters.');
    }
    final prefs = await SharedPreferences.getInstance();
    final all = Map<String, dynamic>.from(
      jsonDecode(prefs.getString(key) ?? '{}') as Map,
    );
    if (text.trim().isEmpty) {
      all.remove(chatId);
    } else {
      all[chatId] = {
        'text': text.trim(),
        'hash': hash(source),
        'ids': source.map((m) => m.id).toList(),
      };
    }
    if (!await prefs.setString(key, jsonEncode(all))) {
      throw StateError('Summary could not be saved.');
    }
  }

  static Future<void> remove(String id) => save(id, '', const []);
}
