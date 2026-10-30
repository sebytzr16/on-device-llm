#include "voice_wav.h"

#include <cstring>
#include <fstream>
#include <iterator>

namespace {
uint32_t U32(const uint8_t* p) {
  return uint32_t(p[0]) | uint32_t(p[1]) << 8 |
         uint32_t(p[2]) << 16 | uint32_t(p[3]) << 24;
}
uint16_t U16(const uint8_t* p) { return uint16_t(p[0]) | uint16_t(p[1]) << 8; }
}  // namespace

std::vector<int16_t> LoadVoiceWav(const std::wstring& path) {
  std::ifstream file(path, std::ios::binary);
  if (!file) return {};
  std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(file)), {});
  if (bytes.size() < 44 || std::memcmp(bytes.data(), "RIFF", 4) ||
      std::memcmp(bytes.data() + 8, "WAVE", 4)) return {};
  int rate = 0;
  const uint8_t* data = nullptr;
  size_t length = 0;
  for (size_t at = 12; at + 8 <= bytes.size();) {
    const size_t size = U32(bytes.data() + at + 4);
    if (size > bytes.size() - at - 8) return {};
    if (!std::memcmp(bytes.data() + at, "fmt ", 4) && size >= 16) {
      const auto* fmt = bytes.data() + at + 8;
      if (U16(fmt) != 1 || U16(fmt + 2) != 1 || U16(fmt + 14) != 16)
        return {};
      rate = static_cast<int>(U32(fmt + 4));
    }
    if (!std::memcmp(bytes.data() + at, "data", 4)) {
      data = bytes.data() + at + 8;
      length = size;
    }
    at += 8 + size + (size & 1);
  }
  if (!data || rate < 8000 || rate > 192000 || length < 2) return {};
  const size_t voiced = length / 2 * 16000 / rate;
  std::vector<int16_t> samples(voiced + 16000);
  for (size_t i = 0; i < voiced; ++i) {
    size_t source = i * static_cast<size_t>(rate) / 16000;
    samples[i] = static_cast<int16_t>(U16(data + source * 2));
  }
  return samples;
}
