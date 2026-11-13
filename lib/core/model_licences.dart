import 'package:flutter/foundation.dart';

/// The models and voices the app offers, with their licences, on the
/// licence page next to the packages (Settings > About). The files are
/// downloaded, not bundled, but CC BY 4.0 asks for the attribution where
/// the work is used. `THIRD_PARTY_NOTICES.md` has the same list.
const modelLicences = <(String, String)>[
  (
    'Parakeet TDT 0.6B v3',
    '"parakeet-tdt-0.6b-v3" by NVIDIA, licensed under CC BY 4.0 '
        '(https://creativecommons.org/licenses/by/4.0/). Source: '
        'https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3. The app uses '
        'the int8 ONNX export made for sherpa-onnx, unchanged. NVIDIA does '
        'not endorse this app.',
  ),
  (
    'Parakeet Ultra',
    '"Parakeet Ultra" by Moondream, licensed under CC BY 4.0 '
        '(https://creativecommons.org/licenses/by/4.0/), derived from '
        'NVIDIA "parakeet-tdt-0.6b-v3". Source: '
        'https://huggingface.co/moondream/parakeet-ultra. The app uses the '
        'int8 ONNX export made for sherpa-onnx, unchanged. Moondream and '
        'NVIDIA do not endorse this app.',
  ),
  (
    'Nemotron 3.5 ASR Streaming 0.6B',
    '"nemotron-3.5-asr-streaming-0.6b" by NVIDIA, licensed under the NVIDIA '
        'Open Model License. Source: '
        'https://huggingface.co/nvidia/nemotron-3.5-asr-streaming-0.6b. The '
        'app uses the int8 ONNX export made for sherpa-onnx, unchanged, for '
        'running captions. NVIDIA does not endorse this app.',
  ),
  (
    'Qwen3.5, Qwen3 and Qwen3.6 / Qwen-Image',
    'Qwen3.5, Qwen3, Qwen3.6 35B, Qwen3-Reranker 0.6B and Qwen-Image 2.1 by the '
        'Qwen team (Alibaba Cloud), licensed under the Apache License 2.0.',
  ),
  (
    'Gemma 4, EmbeddingGemma 2 and DiffusionGemma',
    'Gemma 4, EmbeddingGemma 2 and DiffusionGemma by Google, licensed under '
        'the Apache License 2.0.',
  ),
  (
    'Bonsai 2 (Ternary)',
    'Ternary Bonsai 2 (9B / 27B) by prism-ml, see model card and repository for terms.',
  ),
  (
    'Wan 2.2 TI2V 5B',
    'Wan 2.2 TI2V 5B by QuantStack / Wan-AI, licensed under the Apache License 2.0.',
  ),
  (
    'LTX 2.3 22B',
    'LTX-2.3 22B (Distilled) by Lightricks, licensed under the LTX-2 Community License.',
  ),
  (
    'Upscalers (Nomos2 and Real-ESRGAN)',
    '4xNomos2_hq_mosr (MoSR / Phhofm, CC-BY-4.0) and Real-ESRGAN x4plus (Xinntao, BSD-3-Clause).',
  ),
  (
    'Whisper',
    'Whisper base by OpenAI, licensed under the MIT License. The app uses '
        'the int8 ONNX export made for sherpa-onnx.',
  ),
  (
    'Kokoro 82M',
    'Kokoro 82M v1.0 by hexgrad, licensed under the Apache License 2.0. '
        'The app uses the multi-language ONNX export made for sherpa-onnx.',
  ),
  ('Silero VAD', 'Silero VAD by Silero Team, licensed under the MIT License.'),
  (
    'Supertonic 3',
    'Supertonic 3 by Supertone: OpenRAIL-M (weights), MIT (code). '
        'Model card and weights licence: '
        'https://huggingface.co/Supertone/supertonic-3. '
        'Code: https://github.com/supertone-inc/supertonic. '
        'The app uses the unchanged multilingual int8 export from '
        'https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models '
        '(sherpa-onnx-supertonic-3-tts-int8-2026-05-11.tar.bz2).',
  ),
  (
    'sherpa-onnx and ONNX Runtime',
    'sherpa-onnx by k2-fsa (Apache License 2.0); bundles ONNX Runtime by Microsoft (MIT License).',
  ),
  (
    'llama.cpp and stable-diffusion.cpp',
    'llama.cpp by ggml authors (MIT License) and stable-diffusion.cpp by leejet (MIT License).',
  ),
  ('PDFium', 'PDFium parser engine, licensed under the BSD-3-Clause License.'),
];

/// Adds [modelLicences] to Flutter's licence registry, once.
void registerModelLicences() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(
    () => Stream.fromIterable([
      for (final (name, text) in modelLicences)
        LicenseEntryWithLineBreaks([name], text),
    ]),
  );
}

var _registered = false;
