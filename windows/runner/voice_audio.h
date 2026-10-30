#ifndef RUNNER_VOICE_AUDIO_H_
#define RUNNER_VOICE_AUDIO_H_

#include <windows.h>
#include <mmsystem.h>

#include <array>
#include <deque>
#include <memory>
#include <vector>
#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/method_channel.h>

class VoiceAudio {
 public:
  VoiceAudio(HWND window, flutter::BinaryMessenger* messenger);
  ~VoiceAudio();
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  struct Chunk {
    std::vector<uint8_t> pcm;
    int rate;
    std::unique_ptr<Result> result;
  };
  void StartMic(const Value* args, std::unique_ptr<Result> result);
  void StopMic();
  bool LoadWav(const std::string& path);
  void EmitFrame(const char* bytes);
  void PlayNext();
  void StopPlayback();
  void FinishPlayback(bool heard);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<Value>> method_;
  std::unique_ptr<flutter::EventChannel<Value>> events_;
  std::unique_ptr<flutter::EventSink<Value>> sink_;
  HWAVEIN input_ = nullptr;
  std::array<WAVEHDR, 4> input_headers_{};
  std::array<std::array<char, 1024>, 4> input_bytes_{};
  std::vector<int16_t> wav_samples_;
  size_t wav_offset_ = 0;
  std::deque<Chunk> pending_;
  std::unique_ptr<Chunk> playing_;
  HWAVEOUT output_ = nullptr;
  WAVEHDR output_header_{};
  bool output_prepared_ = false;
  bool interrupted_ = false;
};

#endif
