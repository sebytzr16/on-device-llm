import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/attachments/domain/attachment.dart';
import 'package:ondevice_llm/features/chat/domain/entities/chat_message.dart';
import 'package:ondevice_llm/features/chat/domain/turn_prompts.dart';

void main() {
  test('a non-vision model can read on-device OCR from a photo', () {
    final turn = ChatMessage(
      id: 'question',
      role: ChatRole.user,
      content: 'What is the total?',
      timestamp: DateTime.utc(2026),
      attachments: const [
        Attachment(
          id: 'receipt',
          kind: AttachmentKind.image,
          name: 'receipt.jpg',
          mime: 'image/png',
          path: '/private/receipt.png',
          sizeBytes: 200,
          text: 'Total 19.95',
        ),
      ],
    );
    final rendered = TurnPrompts.renderTurn(turn, vision: false);
    expect(rendered['content'], contains('Total 19.95'));
    // The model cannot see the image: it quotes the text, never sums it.
    expect(rendered['content'], contains('Quote amounts exactly'));
    expect(rendered['content'], isNot(contains('check against the image')));
    expect(
      TurnPrompts.renderTurn(turn, vision: true)['content'],
      contains('check against the image'),
    );
    expect(rendered.containsKey('images'), false);
    final hidden = TurnPrompts.renderTurn(
      turn,
      vision: false,
      documents: false,
    );
    expect(hidden['content'], isNot(contains('Total 19.95')));
  });
}
