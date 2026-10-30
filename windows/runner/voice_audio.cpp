#include "voice_audio.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include "utils.h"
#include "voice_wav.h"

namespace {
constexpr UINT_PTR kWavTimer = 0x564f4943;
constexpr int kRate = 16000;
constexpr int kFrame = 512;

bool MicrophoneDenied() {
  constexpr const wchar_t* keys[] = {
      L"Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\microphone",
      L"Software\\Microsoft\\Windows\\CurrentVersion\\CapabilityAccessManager\\ConsentStore\\microphone\\NonPackaged"};
  for (const auto* key : keys) {
    wchar_t value[32]{};
    DWORD bytes = sizeof(value);
    if (RegGetValueW(HKEY_CURRENT_USER, key, L"Value", RRF_RT_REG_SZ,
                     nullptr, value, &bytes) == ERROR_SUCCESS &&
        _wcsicmp(value, L"Deny") == 0) return true;
  }
  return false;
}

const flutter::EncodableValue* Arg(const flutter::EncodableValue* args,
                                    const char* key) {
  const auto* map = args ? std::get_if<flutter::EncodableMap>(args) : nullptr;
  if (!map) return nullptr;
  auto it = map->find(flutter::EncodableValue(key));
  return it == map->end() ? nullptr : &it->second;
}

}  // namespace

VoiceAudio::VoiceAudio(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  events_ = std::make_unique<flutter::EventChannel<Value>>(
      messenger, "ondevice_llm/voice_audio/mic",
      &flutter::StandardMethodCodec::GetInstance());
  events_->SetStreamHandler(
      std::make_unique<flutter::StreamHandlerFunctions<Value>>(
          [this](const Value*, std::unique_ptr<flutter::EventSink<Value>>&& sink)
              -> std::unique_ptr<flutter::StreamHandlerError<Value>> {
            sink_ = std::move(sink);
            return nullptr;
          },
          [this](const Value*)
              -> std::unique_ptr<flutter::StreamHandlerError<Value>> {
            sink_.reset();
            return nullptr;
          }));
  method_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "ondevice_llm/voice_audio",
      &flutter::StandardMethodCodec::GetInstance());
  method_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& name = call.method_name();
    if (name == "startMic") {
      StartMic(call.arguments(), std::move(result));
    } else if (name == "stopMic") {
      StopMic();
      result->Success();
    } else if (name == "play") {
      auto* bytes = Arg(call.arguments(), "pcm");
      auto* rate = Arg(call.arguments(), "rate");
      const auto* pcm = bytes ? std::get_if<std::vector<uint8_t>>(bytes) : nullptr;
      const auto* hz = rate ? std::get_if<int32_t>(rate) : nullptr;
      if (!pcm || pcm->size() < 2) {
        result->Success(Value(true));
      } else if ((hz && (*hz < 8000 || *hz > 192000)) || pcm->size() % 2) {
        result->Error("audio_format", "Invalid PCM format");
      } else {
        pending_.push_back({*pcm, hz ? *hz : 24000, std::move(result)});
        PlayNext();
      }
    } else if (name == "stopPlayback") {
      StopPlayback();
      result->Success();
    } else if (name == "conversation") {
      result->Success();
    } else if (name == "micPrivacyDenied") {
      result->Success(Value(MicrophoneDenied()));
    } else {
      result->NotImplemented();
    }
  });
}

VoiceAudio::~VoiceAudio() {
  StopMic();
  StopPlayback();
  events_->SetStreamHandler(nullptr);
  method_->SetMethodCallHandler(nullptr);
}

void VoiceAudio::StartMic(const Value* args, std::unique_ptr<Result> result) {
  if (input_ || !wav_samples_.empty()) {
    result->Success(Value(true));
    return;
  }
  const auto* value = Arg(args, "wav");
  const auto* path = value ? std::get_if<std::string>(value) : nullptr;
  if (path && !path->empty()) {
    if (!LoadWav(*path)) {
      result->Error("wav_format", "Expected PCM16 mono WAV");
      return;
    }
    SetTimer(window_, kWavTimer, 32, nullptr);
    result->Success(Value(true));
    return;
  }
  if (MicrophoneDenied()) {
    result->Error("microphone_denied", "Microphone blocked by Windows privacy");
    return;
  }
  WAVEFORMATEX format{WAVE_FORMAT_PCM, 1, kRate, kRate * 2, 2, 16, 0};
  if (waveInOpen(&input_, WAVE_MAPPER, &format,
                 reinterpret_cast<DWORD_PTR>(window_), 0, CALLBACK_WINDOW) !=
      MMSYSERR_NOERROR) {
    input_ = nullptr;
    result->Error("microphone_denied", "Microphone unavailable in Windows");
    return;
  }
  for (size_t i = 0; i < input_headers_.size(); ++i) {
    auto& header = input_headers_[i];
    header.lpData = input_bytes_[i].data();
    header.dwBufferLength = 1024;
    if (waveInPrepareHeader(input_, &header, sizeof(header)) != MMSYSERR_NOERROR ||
        waveInAddBuffer(input_, &header, sizeof(header)) != MMSYSERR_NOERROR) {
      StopMic();
      result->Error("microphone_denied", "Microphone unavailable in Windows");
      return;
    }
  }
  if (waveInStart(input_) != MMSYSERR_NOERROR) {
    StopMic();
    result->Error("microphone_denied", "Microphone unavailable in Windows");
    return;
  }
  result->Success(Value(true));
}

void VoiceAudio::StopMic() {
  KillTimer(window_, kWavTimer);
  wav_samples_.clear();
  wav_offset_ = 0;
  if (!input_) return;
  waveInStop(input_);
  waveInReset(input_);
  for (auto& header : input_headers_) {
    if (header.dwFlags & WHDR_PREPARED)
      waveInUnprepareHeader(input_, &header, sizeof(header));
    header.dwFlags = 0;
  }
  waveInClose(input_);
  input_ = nullptr;
}

bool VoiceAudio::LoadWav(const std::string& path) {
  wav_samples_ = LoadVoiceWav(Utf8ToWide(path));
  wav_offset_ = 0;
  return !wav_samples_.empty();
}

void VoiceAudio::EmitFrame(const char* bytes) {
  if (sink_) sink_->Success(Value(std::vector<uint8_t>(bytes, bytes + 1024)));
}

void VoiceAudio::PlayNext() {
  if (playing_ || pending_.empty()) return;
  playing_ = std::make_unique<Chunk>(std::move(pending_.front()));
  pending_.pop_front();
  WAVEFORMATEX format{WAVE_FORMAT_PCM, 1,
                      static_cast<DWORD>(playing_->rate),
                      static_cast<DWORD>(playing_->rate * 2), 2, 16, 0};
  if (waveOutOpen(&output_, WAVE_MAPPER, &format,
                  reinterpret_cast<DWORD_PTR>(window_), 0, CALLBACK_WINDOW) !=
      MMSYSERR_NOERROR) {
    output_ = nullptr;
    FinishPlayback(false);
    return;
  }
  output_header_ = {};
  output_header_.lpData = reinterpret_cast<LPSTR>(playing_->pcm.data());
  output_header_.dwBufferLength = static_cast<DWORD>(playing_->pcm.size());
  if (waveOutPrepareHeader(output_, &output_header_, sizeof(output_header_)) !=
      MMSYSERR_NOERROR) {
    FinishPlayback(false);
    return;
  }
  output_prepared_ = true;
  if (waveOutWrite(output_, &output_header_, sizeof(output_header_)) !=
      MMSYSERR_NOERROR) FinishPlayback(false);
}

void VoiceAudio::FinishPlayback(bool heard) {
  if (output_) {
    if (output_prepared_)
      waveOutUnprepareHeader(output_, &output_header_, sizeof(output_header_));
    waveOutClose(output_);
    output_ = nullptr;
  }
  output_prepared_ = false;
  if (playing_) {
    playing_->result->Success(Value(heard && !interrupted_));
    playing_.reset();
  }
  interrupted_ = false;
  PlayNext();
}

void VoiceAudio::StopPlayback() {
  for (auto& chunk : pending_) chunk.result->Success(Value(false));
  pending_.clear();
  if (!playing_) return;
  interrupted_ = true;
  if (output_) waveOutReset(output_);
  FinishPlayback(false);
}

bool VoiceAudio::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_TIMER && wparam == kWavTimer) {
    if (wav_samples_.empty()) return true;
    std::array<char, 1024> frame{};
    for (int i = 0; i < kFrame && wav_offset_ < wav_samples_.size(); ++i) {
      const auto v = static_cast<uint16_t>(wav_samples_[wav_offset_++]);
      frame[2 * i] = static_cast<char>(v);
      frame[2 * i + 1] = static_cast<char>(v >> 8);
    }
    EmitFrame(frame.data());
    if (wav_offset_ >= wav_samples_.size()) {
      KillTimer(window_, kWavTimer);
      wav_samples_.clear();
    }
    return true;
  }
  if (message == MM_WIM_DATA) {
    if (input_ && reinterpret_cast<HWAVEIN>(wparam) == input_) {
      auto* header = reinterpret_cast<WAVEHDR*>(lparam);
      if (header && header->dwBytesRecorded == 1024) EmitFrame(header->lpData);
      if (header) waveInAddBuffer(input_, header, sizeof(*header));
    }
    return true;
  }
  if (message == MM_WOM_DONE) {
    if (output_ && reinterpret_cast<HWAVEOUT>(wparam) == output_ &&
        reinterpret_cast<WAVEHDR*>(lparam) == &output_header_)
      FinishPlayback(true);
    return true;
  }
  return false;
}
