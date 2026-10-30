import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_tags.dart';

void main() {
  group('ModelQuantization.tagOf', () {
    test('reads the quant from Hugging Face file names', () {
      expect(ModelQuantization.tagOf('gemma-4-E4B-it-Q8_K_P.gguf'), 'Q8_K_P');
      expect(ModelQuantization.tagOf('Qwen3.5-9B-UD-Q4_K_XL.gguf'), 'Q4_K_XL');
      expect(ModelQuantization.tagOf('model-IQ3_XS.gguf'), 'IQ3_XS');
      expect(ModelQuantization.tagOf('model.BF16.gguf'), 'BF16');
      expect(ModelQuantization.tagOf('gpt-oss-20b-MXFP4.gguf'), 'MXFP4');
      // The hash prefix of a downloaded copy and a folder don't confuse it.
      expect(
        ModelQuantization.tagOf(
          r'C:\models\0123456789abcdef-gemma-4-E4B-it-Q8_0.gguf',
        ),
        'Q8_0',
      );
    });

    test('a version number in the name is not a quant', () {
      expect(ModelQuantization.tagOf('Qwen3.5-0.8B.gguf'), isNull);
      expect(ModelQuantization.tagOf('model.gguf'), isNull);
    });
  });

  group('ModelQuantization.of', () {
    test('maps tags to the nearest family', () {
      expect(ModelQuantization.of('x-Q8_K_P.gguf'), ModelQuantization.q8_0);
      expect(ModelQuantization.of('x-Q8_0.gguf'), ModelQuantization.q8_0);
      expect(ModelQuantization.of('x-Q6_K.gguf'), ModelQuantization.q6_k);
      expect(ModelQuantization.of('x-Q5_K_M.gguf'), ModelQuantization.q5_k_m);
      expect(ModelQuantization.of('x-Q4_0.gguf'), ModelQuantization.q4_0);
      expect(ModelQuantization.of('x-IQ4_NL.gguf'), ModelQuantization.iq4_nl);
      expect(ModelQuantization.of('x-Q4_K_M.gguf'), ModelQuantization.q4_k_m);
      expect(ModelQuantization.of('x-Q3_K_S.gguf'), ModelQuantization.q3_k_m);
      expect(ModelQuantization.of('x-IQ2_XXS.gguf'), ModelQuantization.q2_k);
      expect(ModelQuantization.of('x-F16.gguf'), ModelQuantization.fp16);
      expect(ModelQuantization.of('x.gguf'), ModelQuantization.unknown);
    });
  });

  group('download labels', () {
    test('time left at the current speed', () {
      expect(etaLabel(0, 100, null), isNull);
      expect(etaLabel(0, 0, 10), isNull);
      expect(etaLabel(50, 100, 10), '5s');
      expect(etaLabel(0, 1048576 * 600, 1048576), '10m 0s');
      expect(etaLabel(0, 1048576 * 7300, 1048576), '2h 1m');
    });

    test('bytes and whole percent', () {
      expect(bytesLabel(1048576 * 512), '512 MB');
      expect(bytesLabel(1073741824 * 3 ~/ 2), '1.50 GB');
      expect(wholePercentLabel(0.479), '47%');
    });
  });
}
