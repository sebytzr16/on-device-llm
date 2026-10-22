import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/share/share_inbox.dart';

void main() {
  test('a shared page arrives as its title and link', () {
    final p = SharedPayload.fromMap({
      'text': 'https://example.com/story',
      'subject': 'A good story',
      'files': const [],
    });
    expect(p.draft, 'A good story\nhttps://example.com/story');
    expect(p.isEmpty, false);
  });

  test('a subject already in the text is not repeated', () {
    const p = SharedPayload(
      text: 'A good story https://example.com',
      subject: 'A good story',
    );
    expect(p.draft, 'A good story https://example.com');
    expect(
      const SharedPayload(subject: 'Only a subject').draft,
      'Only a subject',
    );
  });

  test('a subject-only share is a usable draft', () {
    const payload = SharedPayload(subject: 'Article title');
    expect(payload.isEmpty, false);
    expect(payload.draft, 'Article title');
  });

  test('files, skipped files and the platform error are read', () {
    final p = SharedPayload.fromMap({
      'files': [
        {'name': 'report.pdf', 'path': '/cache/shared/0-report.pdf'},
        {'name': 'broken'},
        'junk',
      ],
      'skipped': ['huge.mov'],
      'more': true,
    });
    expect(p.files.map((f) => f.name), ['report.pdf']);
    expect(p.skipped, ['huge.mov']);
    expect(p.more, true);
    expect(p.isEmpty, false);
    expect(SharedPayload.fromMap({'error': 'denied'}).error, 'denied');
    expect(SharedPayload.fromMap(const {}).isEmpty, true);
  });

  test('selected text and launcher entries are recognised', () {
    final selected = SharedPayload.fromMap({
      'text': 'photosynthesis',
      'selection': true,
    });
    expect(selected.selection, isTrue);
    expect(selected.isEmpty, isFalse);
    final voice = SharedPayload.fromMap({'launch': 'voice'});
    expect(voice.launch, 'voice');
    expect(voice.isEmpty, isFalse, reason: 'a launch has no text but acts');
  });
}
