import 'model_info.dart';

/// Static facts about a bundled model that are not persisted per install.
class CatalogMeta {
  final double parameterCountB;
  final bool reasoning;
  final double minRamGb;
  final String blurb;
  const CatalogMeta({
    required this.parameterCountB,
    required this.reasoning,
    required this.minRamGb,
    required this.blurb,
  });
}

/// The multimodal projector (mmproj) that lets a catalog model see photos
/// through llama.cpp's libmtmd. Same publisher revision as the weights.
class VisionProjector {
  final String fileName, downloadUrl, sha256;
  final int sizeBytes;
  const VisionProjector({
    required this.fileName,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
  });
}

// F16 projectors, checked 2026-09-16 via the Hub API (LFS SHA-256).
const visionProjectors = <String, VisionProjector>{
  'qwen35-0.8b-iq4nl': VisionProjector(
    fileName: 'Qwen3.5-0.8B-mmproj-F16.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/6ab461498e2023f6e3c1baea90a8f0fe38ab64d0/mmproj-F16.gguf',
    sha256: '56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453',
    sizeBytes: 204987232,
  ),
  // The everyday 0.8B is bartowski's Q8_0; the projector is the same
  // Qwen3.5-0.8B vision tower, shared on disk with the IQ4_NL entry.
  'qwen35-0.8b-q8_0': VisionProjector(
    fileName: 'Qwen3.5-0.8B-mmproj-F16.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/Qwen3.5-0.8B-GGUF/resolve/6ab461498e2023f6e3c1baea90a8f0fe38ab64d0/mmproj-F16.gguf',
    sha256: '56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453',
    sizeBytes: 204987232,
  ),
  'qwen35-2b-iq4nl': VisionProjector(
    fileName: 'Qwen3.5-2B-mmproj-F16.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae/mmproj-F16.gguf',
    sha256: '7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7',
    sizeBytes: 668227264,
  ),
  'qwen35-4b-iq4nl': VisionProjector(
    fileName: 'Qwen3.5-4B-mmproj-F16.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523/mmproj-F16.gguf',
    sha256: 'cd88edcf8d031894960bb0c9c5b9b7e1fea6ebee02b9f7ce925a00d12891f864',
    sizeBytes: 672423616,
  ),
  'gemma4-e2b-qat': VisionProjector(
    fileName: 'gemma-4-E2B-mmproj-F16.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/gemma-4-E2B-it-qat-GGUF/resolve/66a399f68ddd113b06dff02fca9523e55465d11d/mmproj-F16.gguf',
    sha256: '13c8966d1635d02e6727f27402880614906fa291850c07feda18dbcddf2291b6',
    sizeBytes: 985654080,
  ),
  'gemma4-e4b-qat': VisionProjector(
    fileName: 'gemma-4-E4B-mmproj-F16.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/gemma-4-E4B-it-qat-GGUF/resolve/8c5a9e4fd5482e2be20fe0bf013b4c262a8f4265/mmproj-F16.gguf',
    sha256: '6a255159ee4b01b304f633a57f017dd7d5a69d30fff52abb2614bf0813cef034',
    sizeBytes: 990372672,
  ),
};

/// The embedding model behind the knowledge library's semantic search
/// (FX-02). One model for every collection: passages remember which model
/// indexed them and re-index when it changes.
class EmbeddingModel {
  final String id, displayName, fileName, downloadUrl, sha256;
  final int sizeBytes, dimensions;

  /// Task prefixes the model was trained with (EmbeddingGemma card).
  final String queryPrefix, documentPrefix;

  /// Optional projector that embeds photos and recordings into the same
  /// space as text (EmbeddingGemma 2); a separate, opt-in download.
  final VisionProjector? projector;

  /// Files of earlier embedding models, deleted once this one is used:
  /// their vectors are incompatible and passages re-index anyway.
  final List<String> legacyFileNames;
  const EmbeddingModel({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    required this.dimensions,
    required this.queryPrefix,
    required this.documentPrefix,
    this.projector,
    this.legacyFileNames = const [],
  });

  /// Longest photo side handed to the projector. Its encoder's time grows
  /// with pixels: measured on a Galaxy S25+ (6 threads), 384 px took 1.2 s
  /// a photo, 768 px 2–5 s and 960 px 5–22 s, with the same top-1 results.
  static const mediaImageEdge = 384;

  /// One recording segment per vector: 25 tokens a second must fit the
  /// 2,048-token context with room to spare.
  static const mediaAudioSeconds = 60;
}

// Checked 2026-10-07 via the Hub API (LFS SHA-256), pinned to the revision.
// EmbeddingGemma 2 (Google, 2026): multilingual text, photos and audio in one
// 768-dim space (Matryoshka down to 128), mean pooling, 2k context. Needs
// llama.cpp b11479+ (embeddinggemma2 arch). Text ~310 MB; projector ~555 MB.
const embeddingModel = EmbeddingModel(
  id: 'embeddinggemma-2-q8',
  displayName: 'EmbeddingGemma 2',
  fileName: 'embeddinggemma-2-Q8_0.gguf',
  downloadUrl:
      'https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/bfcd298762cc34d0357ece5ebdd31791a3a374d8/embeddinggemma-2-Q8_0.gguf',
  sha256: '2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135',
  sizeBytes: 309855456,
  dimensions: 256,
  queryPrefix: 'task: search result | query: ',
  documentPrefix: 'title: none | text: ',
  projector: VisionProjector(
    fileName: 'mmproj-embeddinggemma-2-Q8_0.gguf',
    downloadUrl:
        'https://huggingface.co/ggml-org/embeddinggemma-2-GGUF/resolve/bfcd298762cc34d0357ece5ebdd31791a3a374d8/mmproj-embeddinggemma-2-Q8_0.gguf',
    sha256: 'c4a8a52691ecef40618438928bdf9e68379b854e24166f292592353db0aab64f',
    sizeBytes: 554821024,
  ),
  legacyFileNames: ['embeddinggemma-300M-Q8_0.gguf'],
);

/// The optional source-check model: a reranker asked whether a passage
/// states an answer sentence (yes/no), so a sentence that only paraphrases
/// its source is not flagged "not in the sources". Apache-2.0; checked
/// 2026-10-18 via the Hub API (LFS SHA-256).
const supportCheckModel = VisionProjector(
  fileName: 'qwen3-reranker-0.6b-q8_0.gguf',
  downloadUrl:
      'https://huggingface.co/ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF/resolve/a02f48bb4f057028298c21fa033da2b30d7742d5/qwen3-reranker-0.6b-q8_0.gguf',
  sha256: '22c9979ce4fbcdc5acdc310c6641c32797eff1aa980b8f7a2db8a8ea23429a48',
  sizeBytes: 639153184,
);

const catalogMeta = <String, CatalogMeta>{
  'lfm25-2.6b-q4km': CatalogMeta(
    parameterCountB: 2.6,
    reasoning: false,
    minRamGb: 6,
    blurb:
        'Optional experimental text model. Phone speed and quality have not been measured.',
  ),
  'qwen35-2b-iq4nl': CatalogMeta(
    parameterCountB: 2,
    reasoning: true,
    minRamGb: 3,
    blurb:
        'Balanced everyday assistant with visible reasoning. 4-bit IQ4_NL: half the bytes of Q8 per token, so decode is faster on the same phone.',
  ),
  'qwen35-4b-iq4nl': CatalogMeta(
    parameterCountB: 4,
    reasoning: true,
    minRamGb: 6,
    blurb: 'Strongest reasoning in the catalog. Best on 8 GB+ phones.',
  ),
  'gemma4-e4b-qat': CatalogMeta(
    parameterCountB: 4,
    reasoning: true,
    minRamGb: 8,
    blurb: 'Google Gemma 4, effective 4B. Highest quality; needs RAM.',
  ),
  'gemma4-e2b-qat': CatalogMeta(
    parameterCountB: 2,
    reasoning: true,
    minRamGb: 6,
    blurb:
        'Advanced pick: Google Gemma 4, effective 2B. The most accurate small model in Goal research tests (ahead of Qwen3.5 2B); strong writing and languages.',
  ),
  'qwen35-0.8b-q8_0': CatalogMeta(
    parameterCountB: 0.8,
    reasoning: true,
    minRamGb: 2,
    blurb:
        'Everyday pick: fast and light for quick questions and short chats on any phone. 8-bit Q8_0 keeps a small model sharp.',
  ),
  'qwen35-0.8b-iq4nl': CatalogMeta(
    parameterCountB: 0.8,
    reasoning: true,
    minRamGb: 2,
    blurb: 'Fastest useful model. Good for quick questions on any phone.',
  ),
  'qwen3-1.7b-iq4nl': CatalogMeta(
    parameterCountB: 1.7,
    reasoning: true,
    minRamGb: 3,
    blurb:
        'Qwen3 generation, dense. Measured as more precise than Qwen3.5 2B; 40k context, plain KV cache so turns stay resident.',
  ),
};

// Every entry pins an immutable Hugging Face revision and the publisher's LFS
// SHA-256 (Hub API, checked 2026-09-19). All repositories are ungated and
// Apache-2.0 except the explicitly labeled Liquid experiment. The list
// of 2026-09-19, after a memory bandwidth study: every Qwen model as IQ4_NL — decode on the phone is
// bound by the shared DRAM bus, so 4-bit weights are the change that moves
// speed, and IQ4_NL is the 4-bit format llama.cpp repacks for Arm dot-product
// CPUs and that OpenCL and Hexagon read natively — and Gemma 4 E4B/E2B as
// Google's QAT Q4 (UD-Q4_K_XL is the only Q4 file in those repositories;
// their on-disk size is far above their effective parameter count because
// of per-layer embeddings). Nothing else. The earlier Q8_0/Q4_K_M ids are
// retired; a phone that still holds those files keeps them. Since
// 2026-09-24 the 0.8B is Q8_0 again: the tester's everyday model, with
// Gemma 4 E2B as the advanced one.
const bundledCatalog = <ModelInfo>[
  ModelInfo(
    id: 'qwen35-2b-iq4nl',
    displayName: 'Qwen3.5 2B',
    fileName: 'Qwen3.5-2B-IQ4_NL.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae/Qwen3.5-2B-IQ4_NL.gguf',
    sha256: 'e430d87ebc5abbb269c2e2461f1a49b9c5dc79847c13c786dc3615d0b116c4ba',
    sizeBytes: 1213300992,
    family: ModelFamily.qwen,
    quantization: ModelQuantization.iq4_nl,
    license: 'Apache-2.0',
  ),
  ModelInfo(
    id: 'qwen35-4b-iq4nl',
    displayName: 'Qwen3.5 4B',
    fileName: 'Qwen3.5-4B-IQ4_NL.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523/Qwen3.5-4B-IQ4_NL.gguf',
    sha256: 'ff5c3e9740a5aa53f04fdf3b0b8cc75da556bf8948cdb19d61c512d3a43465d9',
    sizeBytes: 2579944608,
    family: ModelFamily.qwen,
    quantization: ModelQuantization.iq4_nl,
    license: 'Apache-2.0',
  ),
  ModelInfo(
    id: 'gemma4-e4b-qat',
    displayName: 'Gemma 4 E4B',
    fileName: 'gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/gemma-4-E4B-it-qat-GGUF/resolve/8c5a9e4fd5482e2be20fe0bf013b4c262a8f4265/gemma-4-E4B-it-qat-UD-Q4_K_XL.gguf',
    sha256: 'df0fd4ee07072c607c29a0a1cb4f98918426cca12f45a2776bdd6ee6d09a4de3',
    sizeBytes: 4215695776,
    family: ModelFamily.gemma,
    quantization: ModelQuantization.q4_k_m,
    license: 'Apache-2.0',
  ),
  ModelInfo(
    id: 'gemma4-e2b-qat',
    displayName: 'Gemma 4 E2B',
    fileName: 'gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/gemma-4-E2B-it-qat-GGUF/resolve/66a399f68ddd113b06dff02fca9523e55465d11d/gemma-4-E2B-it-qat-UD-Q4_K_XL.gguf',
    sha256: 'e531007218dfab990486a5de7676a6932d6ea8dea233d1f698d7c21cf8a16889',
    sizeBytes: 2620370976,
    family: ModelFamily.gemma,
    quantization: ModelQuantization.q4_k_m,
    license: 'Apache-2.0',
  ),
  // 2026-09-24, the tester's everyday model: the 0.8B at Q8_0 (bartowski's
  // quantisation, the file the tester tested) instead of IQ4_NL.
  ModelInfo(
    id: 'qwen35-0.8b-q8_0',
    displayName: 'Qwen3.5 0.8B',
    fileName: 'Qwen_Qwen3.5-0.8B-Q8_0.gguf',
    downloadUrl:
        'https://huggingface.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF/resolve/f36b1ea49a332ede8fe5f389bbf5b3575ef71f48/Qwen_Qwen3.5-0.8B-Q8_0.gguf',
    sha256: '7182e2362766bb9569209bbc24cf1a4cdfbb8ab161babdb2080c84fa62c08c2f',
    sizeBytes: 835325024,
    family: ModelFamily.qwen,
    quantization: ModelQuantization.q8_0,
    license: 'Apache-2.0',
  ),
  ModelInfo(
    id: 'qwen3-1.7b-iq4nl',
    displayName: 'Qwen3 1.7B',
    fileName: 'Qwen3-1.7B-IQ4_NL.gguf',
    downloadUrl:
        'https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/d7f544eead698dbd1f15126ef60b45a1e1933222/Qwen3-1.7B-IQ4_NL.gguf',
    sha256: '54d4991db0f405c5d81c41a22094026cbc37bb2ee445b551bb1754204b5cb680',
    sizeBytes: 1054423616,
    family: ModelFamily.qwen,
    quantization: ModelQuantization.iq4_nl,
    license: 'Apache-2.0',
  ),
];

/// Catalog ids that shipped in earlier builds and were dropped. Their rows
/// are removed on start unless the file is still on the phone.
const retiredCatalogIds = {
  'smollm2-135m-q4km',
  'qwen35-0.8b-q4km',
  'qwen35-2b-q4km',
  'qwen3-1.7b-q4km',
  // 2026-09-19: the Q8_0 / Q4_K_M files gave way to IQ4_NL.
  'qwen35-2b-q8',
  'qwen35-4b-q4km',
  'qwen35-0.8b-q8',
  'qwen3-1.7b-q8',
  // 2026-09-24: the everyday 0.8B is Q8_0 again (Goal tests on the phone).
  'qwen35-0.8b-iq4nl',
  // 2026-10-11: below the 0.8B on the phone at Q4 and Q8 (removed).
  'lfm25-1.2b-qad-q40',
  'granite4-h-1b-q40',
  // 2026-10-18: the tester keeps Gemma 4 and Qwen only (SmolLM3 tried, not good
  // enough; LFM2.5 2.6B was an experiment).
  'lfm25-2.6b-q4km',
  'smollm3-3b-iq4nl',
};
