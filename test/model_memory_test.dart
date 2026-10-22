import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/core/errors/exceptions.dart';
import 'package:ondevice_llm/core/l10n/l10n.dart';
import 'package:ondevice_llm/features/models/presentation/providers/model_manager_provider.dart';

/// Report 2026-09-28: a 64K context made Android kill the app while
/// Qwen3 1.7B loaded. The bridge now shortens the context; the app says so.
void main() {
  final en = stringsFor('en'), fr = stringsFor('fr'), es = stringsFor('es');

  Map<String, dynamic> loaded(int size, int asked, String cap) => {
    'effectiveSettings': {
      'contextSize': size,
      'contextRequested': asked,
      'contextCap': cap,
    },
  };

  test('a context shortened to fit free memory gets a note', () {
    expect(
      contextCapNote(en, loaded(29696, 65536, 'memory')),
      'Context set to 29k tokens so the model fits in free memory.',
    );
    expect(contextCapNote(fr, loaded(29696, 65536, 'memory')), contains('29k'));
    expect(contextCapNote(es, loaded(29696, 65536, 'memory')), contains('29k'));
  });

  test('a context shortened to the trained length says so', () {
    expect(
      contextCapNote(en, loaded(40960, 65536, 'train')),
      'Context set to 40k tokens, the most this model was trained for.',
    );
  });

  test('no note when the load got what it asked for', () {
    expect(contextCapNote(en, loaded(65536, 65536, '')), isNull);
    expect(contextCapNote(en, const {}), isNull);
    // Older bridges report no request: nothing to compare against.
    expect(
      contextCapNote(en, {
        'effectiveSettings': {'contextSize': 4096},
      }),
      isNull,
    );
  });

  test('the bridge refusal is shown in the app language, without a type', () {
    const native =
        'InferenceException: Bad state: Not enough free memory for this model: '
        'it needs about 6120 MB even with a small context, and 4870 MB is '
        'free. Close other apps or choose a smaller model.';
    final e = memoryRefusal(fr, native);
    expect(e, isA<NotEnoughMemoryException>());
    expect('$e', startsWith('Mémoire libre insuffisante'));
    expect('$e', contains('Mo'));
    expect('$e', isNot(contains('Exception')));
    expect('${memoryRefusal(en, native)}', contains('about 6,120 MB'));
    expect(memoryRefusal(en, 'Cannot load this GGUF.'), isNull);
  });
}
