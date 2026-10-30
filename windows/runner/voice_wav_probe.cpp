#include "voice_wav.h"

#include <algorithm>
#include <iostream>

int wmain(int argc, wchar_t** argv) {
  if (argc != 2) return 2;
  auto samples = LoadVoiceWav(argv[1]);
  const auto nonzero = std::count_if(samples.begin(), samples.end(),
                                     [](int16_t v) { return v != 0; });
  if (samples.size() < 16000 || nonzero < 1600) return 1;
  std::cout << "16 kHz samples=" << samples.size()
            << " frames=" << (samples.size() + 511) / 512
            << " nonzero=" << nonzero << '\n';
  return 0;
}
