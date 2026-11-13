#include "voice_audio.h"

#include <algorithm>
#include <cstring>
#include <fstream>
#include <mmdeviceapi.h>
#include <ks.h>
#include <ksmedia.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>
#include "utils.h"
#include "voice_wav.h"

namespace {
constexpr UINT_PTR kWavTimer = 0x564f4943;
constexpr int kRate = 16000;
constexpr int kFrame = 512;
// Closes an idle output device shortly after the last sentence.
constexpr UINT_PTR kOutputIdleTimer = 0x564f4f55;
constexpr UINT_PTR kCaptureTimer = 0x564f4145;

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
      const auto* on = Arg(call.arguments(), "on");
      const auto* call_path = Arg(call.arguments(), "call");
      const bool enabled = on && std::get_if<bool>(on) && std::get<bool>(*on);
      const bool call_enabled = !call_path ||
          (std::get_if<bool>(call_path) && std::get<bool>(*call_path));
      const bool conversation = enabled && call_enabled;
      if (conversation != conversation_) StopMic();
      conversation_ = conversation;
      result->Success();
    } else if (name == "aecActive") {
      result->Success(Value(AecActive()));
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
  if (input_ || capture_audio_ || !wav_samples_.empty()) {
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
  if (conversation_ && StartCommunicationsMic()) {
    result->Success(Value(true));
    return;
  }
  // Communications capture is best effort. Legacy capture remains usable,
  // but AecActive() returns false, so Dart rests the mic during playback.
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
  KillTimer(window_, kCaptureTimer);
  if (capture_audio_) capture_audio_->Stop();
  capture_client_.Reset();
  capture_audio_.Reset();
  aec_reference_set_ = false;
  capture_bytes_ = 0;
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

bool VoiceAudio::StartCommunicationsMic() {
  using Microsoft::WRL::ComPtr;
  ComPtr<IMMDeviceEnumerator> enumerator;
  ComPtr<IMMDevice> device;
  ComPtr<IAudioClient2> audio;
  ComPtr<IAudioCaptureClient> capture;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
          CLSCTX_INPROC_SERVER, IID_PPV_ARGS(enumerator.GetAddressOf()))) ||
      FAILED(enumerator->GetDefaultAudioEndpoint(eCapture, eCommunications,
          device.GetAddressOf())) ||
      FAILED(device->Activate(__uuidof(IAudioClient2), CLSCTX_INPROC_SERVER,
          nullptr, reinterpret_cast<void**>(audio.GetAddressOf())))) return false;

  AudioClientProperties properties{};
  properties.cbSize = sizeof(properties);
  properties.eCategory = AudioCategory_Communications;
  // NONE preserves the system processing/APOs; RAW would disable AEC.
  properties.Options = AUDCLNT_STREAMOPTIONS_NONE;
  WAVEFORMATEX format{WAVE_FORMAT_PCM, 1, kRate, kRate * 2, 2, 16, 0};
  if (FAILED(audio->SetClientProperties(&properties)) ||
      FAILED(audio->Initialize(AUDCLNT_SHAREMODE_SHARED,
          AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
          5000000, 0, &format, nullptr)) ||
      FAILED(audio->GetService(IID_PPV_ARGS(capture.GetAddressOf()))) ||
      FAILED(audio->Start())) return false;
  capture_audio_ = audio;
  capture_client_ = capture;
#ifdef __IAudioEffectsManager_INTERFACE_DEFINED__
  Microsoft::WRL::ComPtr<IAudioEffectsManager> manager;
  if (SUCCEEDED(audio->GetService(IID_PPV_ARGS(manager.GetAddressOf())))) {
    AUDIO_EFFECT* effects = nullptr;
    UINT32 count = 0;
    if (SUCCEEDED(manager->GetAudioEffects(&effects, &count))) {
      for (UINT32 i = 0; i < count; ++i) {
        if (IsEqualGUID(effects[i].id, AUDIO_EFFECT_TYPE_ACOUSTIC_ECHO_CANCELLATION) &&
            effects[i].canSetState && effects[i].state == AUDIO_EFFECT_STATE_OFF) {
          // Best effort: AecActive() independently verifies the resulting state.
          manager->SetAudioEffectState(effects[i].id, AUDIO_EFFECT_STATE_ON);
        }
      }
      CoTaskMemFree(effects);
    }
  }
#endif
#ifdef __IAcousticEchoCancellationControl_INTERFACE_DEFINED__
  // waveOut's WAVE_MAPPER uses the default multimedia render endpoint.
  // Explicitly use that speaker as the AEC reference, even if the user's
  // default communications speaker is a different device.
  ComPtr<IMMDevice> render;
  ComPtr<IAcousticEchoCancellationControl> control;
  LPWSTR render_id = nullptr;
  if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia,
          render.GetAddressOf())) &&
      SUCCEEDED(render->GetId(&render_id)) &&
      SUCCEEDED(audio->GetService(IID_PPV_ARGS(control.GetAddressOf())))) {
    aec_reference_set_ = SUCCEEDED(control->SetEchoCancellationRenderEndpoint(render_id));
  }
  CoTaskMemFree(render_id);
#endif
  capture_bytes_ = 0;
  if (!SetTimer(window_, kCaptureTimer, 10, nullptr)) {
    StopMic();
    return false;
  }
  return true;
}

bool VoiceAudio::AecActive() {
  if (!conversation_ || !capture_audio_ || !aec_reference_set_) return false;
#ifdef __IAudioEffectsManager_INTERFACE_DEFINED__
  // Category selection alone does not prove that this endpoint has AEC.
  // Older Windows versions without this service conservatively report false.
  Microsoft::WRL::ComPtr<IAudioEffectsManager> manager;
  if (FAILED(capture_audio_->GetService(
          IID_PPV_ARGS(manager.GetAddressOf())))) return false;
  AUDIO_EFFECT* effects = nullptr;
  UINT32 count = 0;
  if (FAILED(manager->GetAudioEffects(&effects, &count))) return false;
  bool active = false;
  for (UINT32 i = 0; i < count; ++i) {
    if (IsEqualGUID(effects[i].id, AUDIO_EFFECT_TYPE_ACOUSTIC_ECHO_CANCELLATION) &&
        effects[i].state == AUDIO_EFFECT_STATE_ON) active = true;
  }
  CoTaskMemFree(effects);
  return active;
#else
  return false;
#endif
}

void VoiceAudio::PollCapture() {
  UINT32 available = 0;
  while (capture_client_) {
    if (FAILED(capture_client_->GetNextPacketSize(&available))) {
      StopMic();
      return;
    }
    if (!available) return;
    BYTE* data = nullptr;
    UINT32 frames = 0;
    DWORD flags = 0;
    if (FAILED(capture_client_->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) {
      StopMic();
      return;
    }
    if (flags & AUDCLNT_BUFFERFLAGS_DATA_DISCONTINUITY) capture_bytes_ = 0;
    const size_t bytes = static_cast<size_t>(frames) * 2;
    size_t offset = 0;
    while (offset < bytes) {
      const size_t take = std::min(bytes - offset, capture_frame_.size() - capture_bytes_);
      if (flags & AUDCLNT_BUFFERFLAGS_SILENT)
        std::memset(capture_frame_.data() + capture_bytes_, 0, take);
      else
        std::memcpy(capture_frame_.data() + capture_bytes_, data + offset, take);
      offset += take;
      capture_bytes_ += take;
      if (capture_bytes_ == capture_frame_.size()) {
        EmitFrame(capture_frame_.data());
        capture_bytes_ = 0;
      }
    }
    if (FAILED(capture_client_->ReleaseBuffer(frames))) {
      StopMic();
      return;
    }
  }
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
  // At most two sentences on the device: the playing one and the next.
  while (!pending_.empty() && playing_.size() < 2) {
    const int rate = pending_.front().rate;
    if (output_ && output_rate_ != rate) {
      if (!playing_.empty()) return;  // Reopen once the old rate drains.
      CloseOutput();
    }
    if (!output_) {
      WAVEFORMATEX format{WAVE_FORMAT_PCM, 1, static_cast<DWORD>(rate),
                          static_cast<DWORD>(rate * 2), 2, 16, 0};
      if (waveOutOpen(&output_, WAVE_MAPPER, &format,
                      reinterpret_cast<DWORD_PTR>(window_), 0,
                      CALLBACK_WINDOW) != MMSYSERR_NOERROR) {
        output_ = nullptr;
        pending_.front().result->Success(Value(false));
        pending_.pop_front();
        continue;
      }
      output_rate_ = rate;
    }
    KillTimer(window_, kOutputIdleTimer);
    auto chunk = std::make_unique<Chunk>(std::move(pending_.front()));
    pending_.pop_front();
    chunk->header.lpData = reinterpret_cast<LPSTR>(chunk->pcm.data());
    chunk->header.dwBufferLength = static_cast<DWORD>(chunk->pcm.size());
    if (waveOutPrepareHeader(output_, &chunk->header, sizeof(WAVEHDR)) !=
        MMSYSERR_NOERROR) {
      chunk->result->Success(Value(false));
      continue;
    }
    if (waveOutWrite(output_, &chunk->header, sizeof(WAVEHDR)) !=
        MMSYSERR_NOERROR) {
      waveOutUnprepareHeader(output_, &chunk->header, sizeof(WAVEHDR));
      chunk->result->Success(Value(false));
      continue;
    }
    playing_.push_back(std::move(chunk));
  }
  if (playing_.empty() && pending_.empty() && output_)
    SetTimer(window_, kOutputIdleTimer, 400, nullptr);
}

// The oldest sentence finished playing.
void VoiceAudio::FinishPlayback(bool heard) {
  if (playing_.empty()) return;
  auto chunk = std::move(playing_.front());
  playing_.pop_front();
  if (output_) waveOutUnprepareHeader(output_, &chunk->header, sizeof(WAVEHDR));
  chunk->result->Success(Value(heard));
  PlayNext();
}

void VoiceAudio::CloseOutput() {
  KillTimer(window_, kOutputIdleTimer);
  if (!output_) return;
  waveOutReset(output_);
  for (auto& chunk : playing_) {
    waveOutUnprepareHeader(output_, &chunk->header, sizeof(WAVEHDR));
    chunk->result->Success(Value(false));
  }
  playing_.clear();
  waveOutClose(output_);
  output_ = nullptr;
  output_rate_ = 0;
}

void VoiceAudio::StopPlayback() {
  for (auto& chunk : pending_) chunk.result->Success(Value(false));
  pending_.clear();
  CloseOutput();
}

bool VoiceAudio::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (message == WM_TIMER && wparam == kCaptureTimer) {
    PollCapture();
    return true;
  }
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
        !playing_.empty() &&
        reinterpret_cast<WAVEHDR*>(lparam) == &playing_.front()->header)
      FinishPlayback(true);
    return true;
  }
  if (message == WM_TIMER && wparam == kOutputIdleTimer) {
    KillTimer(window_, kOutputIdleTimer);
    if (playing_.empty() && pending_.empty()) CloseOutput();
    return true;
  }
  return false;
}
