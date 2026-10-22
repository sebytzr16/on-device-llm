import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/retrieval/domain/subject_terms.dart';

void main() {
  group('names from a request', () {
    test('model names, brands and multi-word names', () {
      expect(
        SubjectTerms.of('Compare the nikon z30 to the sony zv-e10.').terms,
        ['nikon z30', 'sony zv-e10'],
      );
      expect(
        SubjectTerms.of(
          'Summarise how the Toronto Blue Jays 2026 season went and what happens next',
        ).terms,
        ['Toronto Blue Jays'],
      );
      expect(
        SubjectTerms.of(
          'Is the Galaxy S25 Ultra worth it over the iPhone 17 Pro?',
        ).terms,
        ['Galaxy S25 Ultra', 'iPhone 17 Pro'],
      );
      expect(
        SubjectTerms.of('compare qwen3.5 2b and gemma 4 e2b for coding').terms,
        ['qwen3.5 2b', 'gemma 4 e2b'],
      );
    });

    test('sentence-initial verbs, years and plain numbers are not names', () {
      expect(
        SubjectTerms.of('Explain how vaccines work in 2026').terms,
        isEmpty,
      );
      expect(
        SubjectTerms.of('Plan 3 days of meals under 50 dollars').terms,
        isEmpty,
      );
    });

    test('quoted phrases are kept word for word', () {
      expect(
        SubjectTerms.of(
          'How do I fix "Unsupported class file major version 65" in Flutter 3.47?',
        ).terms,
        ['Unsupported class file major version 65', 'Flutter 3.47'],
      );
    });
  });

  group('drift', () {
    const cams = SubjectTerms(['nikon z30', 'sony zv-e10']);

    test('another generation of the same model is drift', () {
      expect(cams.drift('The Sony ZV-E10 II has a 26 MP sensor.'), [
        'ZV-E10 II',
      ]);
      expect(cams.drift('The Sony ZV-E10 has a 24 MP sensor.'), isEmpty);
    });

    test(
      'another number in the same line is drift, context required for short codes',
      () {
        const phone = SubjectTerms(['Galaxy S25']);
        expect(phone.drift('The Galaxy S24 has a smaller battery.'), ['S24']);
        expect(phone.drift('Store it in an S3 bucket.'), isEmpty);
        const qwen = SubjectTerms(['Qwen3.5']);
        expect(qwen.drift('Qwen3 was released in 2025.'), ['Qwen3']);
        expect(qwen.drift('Qwen3.5 is fast.'), isEmpty);
        const iphone = SubjectTerms(['iPhone 17']);
        expect(iphone.drift('Unlike the iPhone 16, it has…'), ['iPhone 16']);
      },
    );

    test('names the request itself mentions are not drift', () {
      const phone = SubjectTerms(['Galaxy S25']);
      expect(
        phone.drift(
          'The Galaxy S24 is cheaper.',
          allowed: 'Should I upgrade from the Galaxy S24 to the Galaxy S25?',
        ),
        isEmpty,
      );
    });
  });

  group('mentions', () {
    test('a later generation does not name the original', () {
      expect(
        SubjectTerms.names('Sony ZV-E10 II review', 'sony zv-e10'),
        isFalse,
      );
      expect(SubjectTerms.names('Sony ZV-E10 review', 'sony zv-e10'), isTrue);
      expect(SubjectTerms.names('the ZV-E10 costs', 'sony zv-e10'), isTrue);
      expect(
        SubjectTerms.names(
          'The Blue Jays beat the Yankees',
          'Toronto Blue Jays',
        ),
        isTrue,
      );
    });
  });

  group('repair', () {
    const cams = SubjectTerms(['nikon z30', 'sony zv-e10']);

    test('puts drifted names back and adds the subject when missing', () {
      expect(
        cams.repair('Battery life of the Sony ZV-E10 II vs Nikon Z30'),
        'Battery life of the Sony ZV-E10 vs Nikon Z30',
      );
      expect(
        cams.repair('Determine the maximum video resolutions of each camera.'),
        'Determine the maximum video resolutions of each camera. (nikon z30, sony zv-e10)',
      );
      const phone = SubjectTerms(['Galaxy S25']);
      expect(
        phone.repair('Galaxy S24 battery test results'),
        'Galaxy S25 battery test results',
      );
    });
  });

  group('focus', () {
    test('drops sources about a neighbouring model, keeps on-topic first', () {
      const cams = SubjectTerms(['nikon z30', 'sony zv-e10']);
      final sources = [
        'Webcam resolutions explained',
        'Sony ZV-E10 II review: 26 MP and 4K60',
        'Nikon Z30 vs Sony ZV-E10: which vlogging camera?',
        'Sony ZV-E10 long-term review',
      ];
      // Names the Z30, but its Sony is the II: a different comparison.
      expect(
        cams.replacesTerm(
          'Nikon Z30 vs Sony ZV-E10 II: 26 MP and 759 AF points',
        ),
        isTrue,
      );
      expect(
        cams.replacesTerm('Sony ZV-E10 vs ZV-E10 II vs Nikon Z30 compared'),
        isFalse,
      );
      expect(
        cams.focus([
          'Nikon Z30 vs Sony ZV-E10 II comparison',
          'Nikon Z30 vs Sony ZV-E10: which vlogging camera?',
        ], (s) => s),
        ['Nikon Z30 vs Sony ZV-E10: which vlogging camera?'],
      );
      expect(cams.focus(sources, (s) => s), [
        'Nikon Z30 vs Sony ZV-E10: which vlogging camera?',
        'Sony ZV-E10 long-term review',
      ]);
      expect(cams.focus(sources.take(3).toList(), (s) => s, enough: 2), [
        'Nikon Z30 vs Sony ZV-E10: which vlogging camera?',
        'Webcam resolutions explained',
      ]);
    });
  });
}
