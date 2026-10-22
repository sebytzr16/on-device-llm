import '../../../attachments/domain/attachment.dart';

enum ChatRole { system, user, assistant }

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final String? reasoning;
  final DateTime timestamp;
  final String? modelId;
  final int? tokenCount;
  final String status;
  final String sourcesJson;

  /// Files attached to a user turn; empty for assistant turns.
  final List<Attachment> attachments;

  /// The turn this one continues; null for the first turn of a chat.
  final String? parentId;

  /// `TurnRun` JSON for answers (CHAT-04); null before v8 or for questions.
  final String? runJson;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.reasoning,
    this.modelId,
    this.tokenCount,
    this.status = 'complete',
    this.sourcesJson = '[]',
    this.attachments = const [],
    this.parentId,
    this.runJson,
  });

  /// Comparison identity survives cancellation, errors and process recovery.
  bool get isAlternative =>
      status == 'alternative' || status.startsWith('alternative:');

  String get responseStatus => status == 'alternative'
      ? 'complete'
      : status.startsWith('alternative:')
      ? status.substring('alternative:'.length)
      : status;

  bool get hasImages => attachments.any((a) => a.isImage);

  /// A retained earlier version. Status is
  /// `superseded:<branch>:<original status>` (FX-05), or legacy `superseded`.
  bool get isSuperseded => status.startsWith('superseded');

  /// Branch id of a superseded turn: every turn set aside by the same edit
  /// shares it, so the whole branch can be restored together.
  String? get branch => isSuperseded && status.split(':').length >= 2
      ? status.split(':')[1]
      : null;

  /// The status a superseded turn had before it was set aside.
  String get originalStatus => isSuperseded && status.split(':').length >= 3
      ? status.split(':').sublist(2).join(':')
      : 'complete';

  ChatMessage copyWith({
    String? content,
    String? reasoning,
    int? tokenCount,
    String? status,
    String? sourcesJson,
  }) => ChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    reasoning: reasoning ?? this.reasoning,
    timestamp: timestamp,
    modelId: modelId,
    tokenCount: tokenCount ?? this.tokenCount,
    status: status ?? this.status,
    sourcesJson: sourcesJson ?? this.sourcesJson,
    attachments: attachments,
    parentId: parentId,
    runJson: runJson,
  );
}
