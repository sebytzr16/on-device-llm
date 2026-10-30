#ifndef RUNNER_VOICE_WAV_H_
#define RUNNER_VOICE_WAV_H_

#include <cstdint>
#include <string>
#include <vector>

// Reads a PCM16 mono WAV and resamples it into 16 kHz microphone samples.
std::vector<int16_t> LoadVoiceWav(const std::wstring& path);

#endif
