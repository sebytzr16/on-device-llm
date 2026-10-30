#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ ! -f native/llama.cpp/include/llama.h ]; then
  git clone --depth 1 --branch b11972 https://github.com/ggml-org/llama.cpp.git native/llama.cpp
fi
test "$(git -C native/llama.cpp rev-parse HEAD)" = cf24317bea431b807dc93319d74c61bed6e20aff
# Local changes to the pinned source (native/patches), each applied once.
for patch in native/patches/*.patch; do
  git -C native/llama.cpp apply --reverse --check --ignore-whitespace "$PWD/$patch" 2>/dev/null     || git -C native/llama.cpp apply --ignore-whitespace "$PWD/$patch"
done
flutter pub get
