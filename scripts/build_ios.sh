#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(uname)" == Darwin ]] || { echo 'iOS compilation requires macOS and Xcode.'; exit 1; }
bash scripts/bootstrap.sh
for sdk in iphoneos iphonesimulator; do
  out="$PWD/build/native-ios/$sdk"
  cmake -S native -B "$out" -G Xcode -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk" -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_BUILD_TYPE=Release
  cmake --build "$out" --config Release --target ondevice_llm --parallel 4
  # Merge the bridge and all statically linked ggml/llama dependencies.
  find "$out" -name '*.a' ! -name 'libOnDeviceNative.a' -print0 | \
    xargs -0 xcrun libtool -static -o "$out/libOnDeviceNative.a"
done
output="$PWD/ios/OnDeviceNative/OnDeviceNative.xcframework"
if [[ -e "$output" ]]; then
  echo 'Move the existing ios/OnDeviceNative/OnDeviceNative.xcframework aside before rebuilding.'
  exit 1
fi
xcodebuild -create-xcframework \
  -library "$PWD/build/native-ios/iphoneos/libOnDeviceNative.a" -headers "$PWD/native/src" \
  -library "$PWD/build/native-ios/iphonesimulator/libOnDeviceNative.a" -headers "$PWD/native/src" \
  -output "$output"
echo 'Native libraries ready. Run: cd ios && pod install; then flutter build ios --no-codesign'
