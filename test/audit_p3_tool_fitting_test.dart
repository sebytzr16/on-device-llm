import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/chat/domain/context_use.dart';

void main() {
  test(
    'counts removed exchanges once and preserves the current tool tail',
    () async {
      final messages = <Map<String, Object>>[
        {'role': 'system', 'content': 'instructions'},
        for (var i = 0; i < 100; i++) ...[
          {'role': 'user', 'content': 'question $i'},
          {'role': 'assistant', 'content': 'answer $i'},
        ],
        {'role': 'user', 'content': 'current'},
        {'role': 'assistant', 'tool_calls': <Object>[]},
        {'role': 'tool', 'content': 'evidence'},
      ];
      var calls = 0;
      final removed = await ContextUse.omitToFit(
        messages,
        deficit: 950,
        keep: 2,
        cancelled: () => false,
        count: (exchange) async {
          calls++;
          expect(exchange.length, 2);
          return 10;
        },
      );
      expect(calls, 95);
      expect(removed, 190);
      expect(messages.first['role'], 'system');
      expect(messages[1]['content'], 'question 95');
      expect(messages.last['content'], 'evidence');
    },
  );

  test('respects cancellation and the retained exchange count', () async {
    final messages = <Map<String, Object>>[
      for (var i = 0; i < 4; i++) ...[
        {'role': 'user', 'content': '$i'},
        {'role': 'assistant', 'content': 'answer'},
      ],
    ];
    expect(
      await ContextUse.omitToFit(
        messages,
        deficit: 100,
        keep: 2,
        cancelled: () => false,
        count: (_) async => 1,
      ),
      2,
    );
    expect(
      await ContextUse.omitToFit(
        messages,
        deficit: 100,
        keep: 0,
        cancelled: () => true,
        count: (_) async => 1,
      ),
      0,
    );
  });
}
