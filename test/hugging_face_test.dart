import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';

void main() {
  test('files carry quantization, projector and split flags', () {
    const q4 = HfFile(name: 'Qwen3-4B-Q4_K_M.gguf', size: 1, sha256: 'a');
    const f16 = HfFile(name: 'model-F16.gguf', size: 1, sha256: 'b');
    const proj = HfFile(name: 'mmproj-F16.gguf', size: 1, sha256: 'c');
    const split = HfFile(
      name: 'big-Q8_0-00001-of-00003.gguf',
      size: 1,
      sha256: 'd',
    );
    expect(q4.quantization, ModelQuantization.q4_k_m);
    expect(f16.quantization, ModelQuantization.fp16);
    expect(proj.isProjector, true);
    expect(split.isSplit, true);
    expect(q4.isProjector || q4.isSplit, false);
  });

  test('family is guessed from the repository and the entry is pinned', () {
    expect(HuggingFace.guessFamily('unsloth/Qwen3-4B-GGUF'), ModelFamily.qwen);
    expect(
      HuggingFace.guessFamily('bartowski/gemma-4-9b-it-GGUF'),
      ModelFamily.gemma,
    );
    expect(
      HuggingFace.guessFamily('microsoft/Phi-4-mini-GGUF'),
      ModelFamily.phi,
    );
    expect(HuggingFace.guessFamily('someone/Mystery-GGUF'), ModelFamily.other);
    const repo = HfRepoFiles(
      repo: 'unsloth/Qwen3-4B-GGUF',
      revision: 'abc123',
      license: 'apache-2.0',
      files: [HfFile(name: 'Qwen3-4B-Q4_K_M.gguf', size: 2000, sha256: 'ff')],
    );
    final m = HuggingFace.modelFor(repo, repo.files.single, ModelFamily.qwen);
    expect(m.id, startsWith('hf-'));
    expect(m.displayName, 'Qwen3-4B-Q4_K_M');
    expect(m.fileName, endsWith('-Qwen3-4B-Q4_K_M.gguf'));
    expect(
      m.downloadUrl,
      'https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/abc123/Qwen3-4B-Q4_K_M.gguf',
    );
    expect(m.sha256, 'ff');
    expect(m.license, 'apache-2.0');
    // Same file → same id, so re-adding does not duplicate the entry.
    expect(
      HuggingFace.modelFor(repo, repo.files.single, ModelFamily.other).id,
      m.id,
    );
  });
}
