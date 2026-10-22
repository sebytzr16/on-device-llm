#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f native/llama.cpp/include/llama.h ]; then
  git clone --depth 1 --branch b11479 https://github.com/ggml-org/llama.cpp.git native/llama.cpp
fi
test "$(git -C native/llama.cpp rev-parse HEAD)" = 42c787e8c191d49c01c757f4b7029d69ec0bf2c8
flutter pub get
