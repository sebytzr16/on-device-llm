import '../../../data/network/web_search/search_models.dart';
import 'entities/chat_message.dart';

/// A bounded, local audit of context selection. Excerpts are for inspection;
/// they are never automatically substituted for the original conversation.
class ContextUse {
  static Map<String, dynamic> capture({
    required List<ChatMessage> available,
    required List<ChatMessage> requested,
    required int omitted,
    required String instructions,
    required List<SearchResult> sources,
    required bool isolated,
    String? documentNotice,
    Set<String> summarizedIds = const {},
  }) {
    final count = omitted.clamp(
      0,
      (requested.length - 1).clamp(0, requested.length),
    );
    final requestedIds = requested.map((m) => m.id).toSet();
    final omittedIds = requested.take(count).map((m) => m.id).toSet();
    return {
      'version': 1,
      'isolated': isolated,
      'instructionChars': instructions.length,
      'instructions': excerpt(instructions, 6000),
      'documentNotice': ?documentNotice,
      'availableMessages': available.length,
      'includedMessages': requested.length - count,
      'omittedMessages': available.length - requested.length + count,
      'earlierEntriesHidden': (available.length - 100).clamp(
        0,
        available.length,
      ),
      'turns': [
        for (final m in available.skip(
          (available.length - 100).clamp(0, available.length),
        ))
          {
            'id': m.id,
            'role': m.role.name,
            'excerpt': excerpt(m.content, 240),
            'chars': m.content.length,
            'images': m.attachments.where((a) => a.isImage).length,
            'documents': m.attachments.where((a) => !a.isImage).length,
            'included':
                requestedIds.contains(m.id) && !omittedIds.contains(m.id),
            'reason': !requestedIds.contains(m.id)
                ? summarizedIds.contains(m.id)
                      ? 'reviewed_summary'
                      : 'isolated'
                : omittedIds.contains(m.id)
                ? 'context_limit'
                : '',
          },
      ],
      'sources': [
        for (var i = 0; i < sources.length; i++)
          {
            'number': i + 1,
            'title': sources[i].title,
            'url': sources[i].finalUrl ?? sources[i].url,
            'chars': (sources[i].pageText ?? sources[i].snippet).length,
            'snippetOnly': sources[i].pageText == null,
            'stale': sources[i].stale,
            'coverage': sources[i].coverage,
            'archiveDate': ?sources[i].archiveDate,
            'archiveId': ?sources[i].archiveId,
            if (sources[i].fetchedAt != null)
              'retrievedAt': sources[i].fetchedAt!.toIso8601String(),
          },
      ],
    };
  }

  static String excerpt(String text, int limit) =>
      text.length <= limit ? text : '${text.substring(0, limit)}…';

  /// Same exchange boundary used by the native engine: keep the system
  /// message and current question with all of its tool-call/results tail.
  /// Nothing is removed while [keep] or fewer earlier exchanges remain: the
  /// last exchanges say what the conversation is about, so callers trim
  /// evidence before they drop them (report 2026-10-04: a follow-up
  /// after a web search had forgotten the topic, because the evidence of
  /// the new turn pushed every earlier exchange out of a 4K context).
  static int omitOldestExchange(
    List<Map<String, Object>> messages, {
    int keep = 0,
  }) {
    final start = messages.isNotEmpty && messages.first['role'] == 'system'
        ? 1
        : 0;
    final lastUser = messages.lastIndexWhere((m) => m['role'] == 'user');
    if (lastUser <= start) return 0;
    if (keep > 0 && earlierExchanges(messages) <= keep) return 0;
    var end = start + 1;
    while (end < lastUser && messages[end]['role'] != 'user') {
      end++;
    }
    messages.removeRange(start, end);
    return end - start;
  }

  /// Removes every exchange before the current question and returns the
  /// user's last [keep] earlier messages, oldest first, quoted and joined
  /// (null when there was none), for a turn that must not read earlier
  /// answers but should still know what the user said.
  static String? dropEarlierExchanges(
    List<Map<String, Object>> messages, {
    int keep = 3,
  }) {
    final start = messages.isNotEmpty && messages.first['role'] == 'system'
        ? 1
        : 0;
    final lastUser = messages.lastIndexWhere((m) => m['role'] == 'user');
    if (lastUser <= start) return null;
    final said = <String>[];
    for (var i = start; i < lastUser; i++) {
      final c = messages[i]['content'];
      if (messages[i]['role'] == 'user' && c is String && c.trim().isNotEmpty) {
        final t = c.trim();
        said.add(t.length > 200 ? '${t.substring(0, 200)}…' : t);
      }
    }
    messages.removeRange(start, lastUser);
    if (said.isEmpty) return null;
    return said
        .skip(said.length > keep ? said.length - keep : 0)
        .map((t) => '“$t”')
        .join(' ');
  }

  /// Exchanges before the current question (user turns that start one).
  static int earlierExchanges(List<Map<String, Object>> messages) {
    final lastUser = messages.lastIndexWhere((m) => m['role'] == 'user');
    if (lastUser < 0) return 0;
    var count = 0;
    var inExchange = false;
    for (var i = 0; i < lastUser; i++) {
      final role = messages[i]['role'];
      if (role == 'system') continue;
      if (role == 'user' && !inExchange) count++;
      inExchange = role == 'user';
    }
    return count;
  }
}
