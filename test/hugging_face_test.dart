import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondevice_llm/data/network/hugging_face.dart';
import 'package:ondevice_llm/features/models/domain/entities/model_info.dart';

void main() {
  test('projector selection prefers F16 then BF16 then smallest', () {
    const f16 = HfFile(name: 'mmproj-F16.gguf', size: 900, sha256: 'f16');
    const bf16 = HfFile(name: 'mmproj-BF16.gguf', size: 800, sha256: 'bf16');
    const f32 = HfFile(name: 'mmproj-F32.gguf', size: 100, sha256: 'f32');
    const other = HfFile(name: 'mmproj-Q8.gguf', size: 200, sha256: 'q8');
    expect(HuggingFace.selectProjector([bf16, f32, f16]), same(f16));
    expect(HuggingFace.selectProjector([f32, bf16]), same(bf16));
    expect(HuggingFace.selectProjector([other, f32]), same(f32));
    expect(HuggingFace.selectProjector([]), isNull);
    const weights = HfFile(
      name: 'model-Q4_K_M.gguf',
      size: 1000,
      sha256: 'weights',
    );
    const repo = HfRepoFiles(
      repo: 'publisher/vision',
      revision: 'revision',
      license: 'apache-2.0',
      files: [weights, f16],
    );
    final model = HuggingFace.modelFor(repo, weights, ModelFamily.qwen);
    expect(model.copyWith(isDownloaded: true).projector?.sha256, 'f16');
    expect(
      model.projector?.downloadUrl,
      contains('/resolve/revision/mmproj-F16.gguf'),
    );
    expect(
      HuggingFace.modelFor(
        repo,
        weights,
        ModelFamily.qwen,
        includeProjector: false,
      ).projector,
      isNull,
    );
  });

  test('the projector matches the base model (P2-42)', () {
    const small = HfFile(
      name: 'mmproj-Qwen3-VL-2B-F16.gguf',
      size: 1,
      sha256: 'a',
    );
    const big = HfFile(
      name: 'mmproj-Qwen3-VL-8B-F16.gguf',
      size: 2,
      sha256: 'b',
    );
    const model = HfFile(name: 'Qwen3-VL-8B-Q4_K_M.gguf', size: 9, sha256: 'c');
    expect(HuggingFace.selectProjector([small, big], model: model), same(big));
    const a = HfFile(name: 'A/mmproj-F16.gguf', size: 1, sha256: 'd');
    const b = HfFile(name: 'B/mmproj-F16.gguf', size: 2, sha256: 'e');
    const inB = HfFile(name: 'B/model-Q8_0.gguf', size: 9, sha256: 'f');
    expect(HuggingFace.selectProjector([a, b], model: inB), same(b));
    // One projector per repo: still chosen by precision.
    const bf = HfFile(name: 'mmproj-BF16.gguf', size: 1, sha256: 'g');
    const f16 = HfFile(name: 'mmproj-F16.gguf', size: 2, sha256: 'h');
    expect(HuggingFace.selectProjector([bf, f16], model: model), same(f16));
  });

  test('a pasted link keeps its revision (P2-41)', () async {
    final dio = Dio();
    addTearDown(dio.close);
    String? asked;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          asked = options.path;
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'sha': 'abc123',
                'siblings': [
                  {
                    'rfilename': 'm-Q4_K_M.gguf',
                    'lfs': {'sha256': 'a' * 64, 'size': 10},
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    final m = await HuggingFace.resolve(
      'https://huggingface.co/pub/model/resolve/v2/m-Q4_K_M.gguf',
      ModelFamily.qwen,
      client: dio,
    );
    expect(asked, endsWith('/api/models/pub/model/revision/v2'));
    expect(m.downloadUrl, contains('/resolve/abc123/'));
  });

  test('Hub siblings include nested splits, grouped in loader order', () async {
    final dio = Dio();
    addTearDown(dio.close);
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          expect(options.queryParameters['blobs'], true);
          handler.resolve(
            Response(
              requestOptions: options,
              data: {
                'sha': 'pinned',
                'gated': false,
                'cardData': {'license': 'apache-2.0'},
                'siblings': [
                  for (final i in [2, 1, 3])
                    {
                      'rfilename': 'Q4_K_M/model-Q4_K_M-0000$i-of-00003.gguf',
                      'lfs': {'sha256': '$i' * 64, 'size': i * 100},
                    },
                  {'rfilename': 'README.md'},
                  {
                    'rfilename': 'other/incomplete-00001-of-00002.gguf',
                    'lfs': {'sha256': 'f' * 64, 'size': 50},
                  },
                ],
              },
            ),
          );
        },
      ),
    );
    final repo = await HuggingFace.files('publisher/model', client: dio);
    expect(repo.files, hasLength(4));
    final first = repo.models.single;
    expect(first.displayName, 'Q4_K_M/model-Q4_K_M.gguf');
    expect(repo.totalSize(first), 600);
    final m = HuggingFace.modelFor(
      repo,
      repo.files.firstWhere((f) => f.name.endsWith('00002-of-00003.gguf')),
      ModelFamily.qwen,
    );
    expect(m.fileName, endsWith('-model-Q4_K_M-00001-of-00003.gguf'));
    expect(m.parts.map((f) => f.sha256), ['1' * 64, '2' * 64, '3' * 64]);
    expect(m.parts.first.fileName, m.fileName);
    expect(
      m.parts.every((f) => f.fileName.startsWith(m.id.substring(3))),
      true,
    );
    expect(
      m.downloadUrl,
      endsWith('/resolve/pinned/Q4_K_M/model-Q4_K_M-00001-of-00003.gguf'),
    );
    expect(m.sizeBytes, 600);
    expect(m.displayName, 'model');
    expect(m.copyWith(isDownloaded: true).parts, same(m.parts));
    expect(
      ModelDownloadPart.fromJson(
        jsonDecode(jsonEncode(m.parts[1].toJson())),
      ).sha256,
      '2' * 64,
    );
    expect(
      () => HuggingFace.modelFor(
        repo,
        repo.files.firstWhere((f) => f.name.startsWith('other/')),
        ModelFamily.qwen,
      ),
      throwsFormatException,
    );
  });

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
    // A distill uses its teacher's prompt; "phi" inside a word is not Phi.
    expect(
      HuggingFace.guessFamily('unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF'),
      ModelFamily.deepseek,
    );
    expect(
      HuggingFace.guessFamily('TheBloke/dolphin-2.6-mistral-7B-GGUF'),
      ModelFamily.mistral,
    );
    const repo = HfRepoFiles(
      repo: 'unsloth/Qwen3-4B-GGUF',
      revision: 'abc123',
      license: 'apache-2.0',
      files: [HfFile(name: 'Qwen3-4B-Q4_K_M.gguf', size: 2000, sha256: 'ff')],
    );
    final m = HuggingFace.modelFor(repo, repo.files.single, ModelFamily.qwen);
    expect(m.id, startsWith('hf-'));
    expect(m.displayName, 'Qwen3 4B');
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
