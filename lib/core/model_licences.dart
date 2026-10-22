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
    'Qwen3.5 and Qwen3',
    'Qwen3.5 0.8B, 2B and 4B, Qwen3 1.7B and Qwen3-Reranker 0.6B by the '
        'Qwen team (Alibaba Cloud), licensed under the Apache License 2.0.',
  ),
  (
    'Gemma 4 and EmbeddingGemma 2',
    'Gemma 4 E2B and E4B and EmbeddingGemma 2 by Google, licensed under '
        'the Apache License 2.0.',
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
    'sherpa-onnx',
    'sherpa-onnx by k2-fsa (Next-gen Kaldi), licensed under the Apache '
        'License 2.0; it bundles ONNX Runtime by Microsoft (MIT License).',
  ),
  (
    'llama.cpp',
    'llama.cpp and ggml by the ggml authors, licensed under the MIT '
        'License.',
  ),
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
