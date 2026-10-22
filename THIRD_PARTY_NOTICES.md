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

Dart and Flutter packages keep their own licences. The app's licence page
(Settings > About > Open-source licences) lists them, with the models below.

## Models offered in the app

| Model | Use | Licence | Source |
|---|---|---|---|
| Qwen3.5 0.8B / 2B / 4B, Qwen3 1.7B | Chat | Apache-2.0 | Qwen (Alibaba) on Hugging Face |
| Gemma 4 E2B / E4B | Chat | Apache-2.0 | Google on Hugging Face |
| EmbeddingGemma 2 (text and projector) | Search ranking, memory | Apache-2.0 | `ggml-org/embeddinggemma-2-GGUF` |
| Qwen3-Reranker 0.6B Q8_0 | Optional source check | Apache-2.0 | `ggml-org/Qwen3-Reranker-0.6B-Q8_0-GGUF` |
| Whisper base (int8, sherpa-onnx export) | Listening | MIT | `csukuangfj/sherpa-onnx-whisper-base` (OpenAI Whisper) |
| Parakeet TDT 0.6B v3 (int8, sherpa-onnx export) | Optional listening | CC-BY-4.0 | `csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` |
| Silero VAD | Speech detection | MIT | https://github.com/snakers4/silero-vad |
| Kokoro 82M v1.0 (multi-language) | Speaking | Apache-2.0 | `k2-fsa/sherpa-onnx` tts-models release (hexgrad/Kokoro-82M) |

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
