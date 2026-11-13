# Third-party notices

The app's own code is MIT licensed (`LICENSE`). The app downloads model files
only when the user asks for them, from pinned revisions. The files are not
in this repository, and each keeps its own licence.

## Runtimes

| Component | Licence | Source |
|---|---|---|
| llama.cpp / ggml | MIT | https://github.com/ggml-org/llama.cpp (vendored in `native/llama.cpp`) |
| sherpa-onnx | Apache-2.0 | https://github.com/k2-fsa/sherpa-onnx (`sherpa_onnx` package) |
| ONNX Runtime (bundled with sherpa-onnx) | MIT | https://github.com/microsoft/onnxruntime |
| stable-diffusion.cpp | MIT | https://github.com/leejet/stable-diffusion.cpp (vendored in `native/diffusiongemma`) |
| PDFium (via pdfrx / PDF parser) | BSD-3-Clause | https://pdfium.googlesource.com/pdfium |

Dart and Flutter packages keep their own licences. The app's licence page
(Settings > About > Open-source licences) lists them, with the models below.

## Models offered in the app

| Model | Use | Licence | Source |
|---|---|---|---|
| Qwen3.5 0.8B / 2B / 4B, Qwen3 1.7B, Qwen3.6 35B, Qwen3.5 9B | Chat / Vision | Apache-2.0 | Qwen (Alibaba) on Hugging Face |
| Gemma 4 E2B / E4B / 26B, EmbeddingGemma 2 | Chat / Search / Vision | Apache-2.0 | Google on Hugging Face |
| Qwen3-Reranker 0.6B Q8_0 | Optional source check | Apache-2.0 | `ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF` |
| DiffusionGemma 26B | Text generation (diffusion) | Apache-2.0 | Google / Unsloth on Hugging Face |
| Bonsai 2 9B / 27B (Ternary) | Chat / Vision | See model card | `prism-ml` on Hugging Face |
| Qwen-Image 2.1 (Q8 / Q4K) | Image generation | Apache-2.0 | `leejet/Qwen-Image-2.1-GGUF` |
| Wan 2.2 TI2V 5B | Video generation | Apache-2.0 | `QuantStack/Wan2.2-TI2V-5B-GGUF` |
| LTX 2.3 22B (Distilled) | Video generation | LTX-2 Community License | `unsloth/LTX-2.3-GGUF` |
| 4xNomos2_hq_mosr / Real-ESRGAN x4plus | Upscaling | CC-BY-4.0 / BSD-3-Clause | GitHub releases / Xinntao |
| Whisper base (int8, sherpa-onnx export) | Listening | MIT | `csukuangfj/sherpa-onnx-whisper-base` (OpenAI Whisper) |
| Parakeet TDT 0.6B v3 (int8, sherpa-onnx export) | Optional listening | CC-BY-4.0 | `csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` |
| Silero VAD | Speech detection | MIT | https://github.com/snakers4/silero-vad |
| Kokoro 82M v1.0 (multi-language) | Speaking | Apache-2.0 | `k2-fsa/sherpa-onnx` tts-models release (hexgrad/Kokoro-82M) |
| Supertonic 2 (multilingual int8) | Optional speaking, EN/FR/ES | OpenRAIL-M weights; MIT code | [Official sherpa-onnx pack](https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-supertonic-tts-int8-2026-03-06.tar.bz2), Supertone |

Supertonic 2 weights retain the [OpenRAIL-M licence and use restrictions](https://huggingface.co/Supertone/supertonic-2/blob/main/LICENSE).
The [Supertonic code](https://github.com/supertone-inc/supertonic) is MIT licensed;
that does not change the weights licence. The app downloads the unchanged
sherpa-onnx export only on request and preserves the archive's licence file.

### Attribution: Parakeet TDT 0.6B v3

"parakeet-tdt-0.6b-v3" by NVIDIA, licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Source:
https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3. The app uses the int8
ONNX export made for sherpa-onnx, unchanged. NVIDIA does not endorse this
app.

## Models the user imports

A GGUF the user imports or finds through the Hugging Face search keeps the
licence its publisher gives it. The app shows the licence the Hub reports
before the download, when there is one.
