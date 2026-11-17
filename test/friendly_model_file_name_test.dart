import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/features/models/presentation/widgets/model_categories.dart';

void main() {
  test('hub hash, extension and underscores go; the quant stays', () {
    expect(
      friendlyModelFileName(
        r'C:\models\30463452c5fe143f-mtp-Qwen_Qwen3.6-35B-A3B-Q8_0.gguf',
      ),
      'mtp-Qwen Qwen3.6-35B-A3B Q8_0',
    );
    expect(
      friendlyModelFileName('/data/mmproj-gemma-4-e2b-f16.gguf'),
      'mmproj-gemma-4-e2b F16',
    );
    expect(friendlyModelFileName('kokoro-v1.0.onnx'), 'kokoro-v1.0');
    expect(
      friendlyModelFileName('embeddinggemma-300M-Q4_K_M.gguf'),
      'embeddinggemma-300M Q4_K_M',
    );
  });
}
