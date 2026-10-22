class ReasoningBlock {
  final String id;
  final String content;
  final bool isComplete;
  final Duration? elapsed;

  const ReasoningBlock({
    required this.id,
    required this.content,
    this.isComplete = false,
    this.elapsed,
  });

  ReasoningBlock copyWith({
    String? content,
    bool? isComplete,
    Duration? elapsed,
  }) => ReasoningBlock(
    id: id,
    content: content ?? this.content,
    isComplete: isComplete ?? this.isComplete,
    elapsed: elapsed ?? this.elapsed,
  );
}
