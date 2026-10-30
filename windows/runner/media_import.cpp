#include "media_import.h"

#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <wrl/client.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Graphics.Imaging.h>
#include <winrt/Windows.Media.Ocr.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <array>
#include <filesystem>
#include <fstream>
#include <stdexcept>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using Microsoft::WRL::ComPtr;
constexpr UINT kMediaComplete = WM_APP + 0x71;
constexpr DWORD kAudioStream = static_cast<DWORD>(MF_SOURCE_READER_FIRST_AUDIO_STREAM);
std::string StringArg(const Map& args, const char* name) {
  const auto it = args.find(Value(name));
  if (it == args.end()) return {};
  const auto* value = std::get_if<std::string>(&it->second);
  return value ? *value : std::string();
}
void Check(HRESULT hr) { winrt::check_hresult(hr); }
struct MfSession {
  MfSession() { Check(MFStartup(MF_VERSION)); }
  ~MfSession() { MFShutdown(); }
};
void CheckCancelled(const std::atomic_bool& cancelled) {
  if (cancelled) throw std::runtime_error("Audio import cancelled.");
}
Value Decode(const std::string& path, const std::string& out, int limit,
             const std::atomic_bool& cancelled) {
  const auto source = std::filesystem::absolute(winrt::to_hstring(path).c_str());
  const auto destination = std::filesystem::absolute(winrt::to_hstring(out).c_str());
  if (source.lexically_normal() == destination.lexically_normal() ||
      (std::filesystem::exists(destination) &&
       std::filesystem::equivalent(source, destination))) {
    throw std::runtime_error("Audio output must differ from the recording.");
  }
  MfSession mf;
  ComPtr<IMFSourceReader> reader;
  Check(MFCreateSourceReaderFromURL(source.c_str(), nullptr, &reader));
  Check(reader->SetStreamSelection(static_cast<DWORD>(MF_SOURCE_READER_ALL_STREAMS), FALSE));
  Check(reader->SetStreamSelection(kAudioStream, TRUE));
  ComPtr<IMFMediaType> type;
  Check(MFCreateMediaType(&type));
  Check(type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio));
  Check(type->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM));
  Check(type->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, 1));
  Check(type->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, 16000));
  Check(type->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16));
  Check(type->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, 2));
  Check(type->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 32000));
  // Source Reader inserts the audio decoder and resampler for this PCM type.
  Check(reader->SetCurrentMediaType(kAudioStream,
                                  nullptr, type.Get()));
  std::ofstream file(destination, std::ios::binary | std::ios::trunc);
  if (!file) throw std::runtime_error("Cannot create decoded recording.");
  try {
    std::array<char, 44> header{};
    file.write(header.data(), header.size());
    uint32_t written = 0;
    const uint32_t maximum = static_cast<uint32_t>(limit) * 32000;
    bool truncated = false;
    for (;;) {
      CheckCancelled(cancelled);
      DWORD flags = 0;
      ComPtr<IMFSample> sample;
      Check(reader->ReadSample(kAudioStream, 0, nullptr,
                               &flags, nullptr, &sample));
      if (flags & MF_SOURCE_READERF_ERROR) {
        throw std::runtime_error("Audio decoder failed.");
      }
      if (flags & MF_SOURCE_READERF_CURRENTMEDIATYPECHANGED) {
        throw std::runtime_error("Audio format changes mid-recording.");
      }
      if (sample) {
        ComPtr<IMFMediaBuffer> buffer;
        Check(sample->ConvertToContiguousBuffer(&buffer));
        BYTE* data = nullptr;
        DWORD size = 0;
        Check(buffer->Lock(&data, nullptr, &size));
        const auto count = std::min<uint32_t>(size, maximum - written) & ~1u;
        file.write(reinterpret_cast<const char*>(data), count);
        buffer->Unlock();
        written += count;
        if (size > count) { truncated = true; break; }
      }
      if (!file) throw std::runtime_error("Cannot write decoded recording.");
      if (flags & MF_SOURCE_READERF_ENDOFSTREAM) break;
    }
    CheckCancelled(cancelled);
    auto tag = [&](size_t at, const char* text) {
      std::copy_n(text, 4, header.data() + at);
    };
    auto number = [&](size_t at, uint32_t value, size_t bytes) {
      for (size_t i = 0; i < bytes; ++i)
        header[at + i] = static_cast<char>((value >> (8 * i)) & 255);
    };
    tag(0, "RIFF"); number(4, 36 + written, 4); tag(8, "WAVE");
    tag(12, "fmt "); number(16, 16, 4); number(20, 1, 2);
    number(22, 1, 2); number(24, 16000, 4); number(28, 32000, 4);
    number(32, 2, 2); number(34, 16, 2); tag(36, "data");
    number(40, written, 4);
    file.seekp(0); file.write(header.data(), header.size()); file.close();
    if (!file) throw std::runtime_error("Cannot finish decoded recording.");
    return Value(Map{{Value("path"), Value(out)},
                     {Value("seconds"), Value(written / 32000.0)},
                     {Value("truncated"), Value(truncated)}});
  } catch (...) {
    file.close();
    std::error_code ignored;
    std::filesystem::remove(destination, ignored);
    throw;
  }
}
Value Recognize(const std::string& path) {
  using namespace winrt::Windows;
  auto engine = Media::Ocr::OcrEngine::TryCreateFromUserProfileLanguages();
  if (!engine) throw std::runtime_error(
      "OCR unavailable. Install an OCR language in Windows language settings.");
  const auto absolute = std::filesystem::absolute(winrt::to_hstring(path).c_str());
  auto file = Storage::StorageFile::GetFileFromPathAsync(absolute.c_str()).get();
  auto stream = file.OpenAsync(Storage::FileAccessMode::Read).get();
  auto decoder = Graphics::Imaging::BitmapDecoder::CreateAsync(stream).get();
  auto transform = Graphics::Imaging::BitmapTransform();
  const auto edge = std::max(decoder.PixelWidth(), decoder.PixelHeight());
  const auto maximum = Media::Ocr::OcrEngine::MaxImageDimension();
  if (edge > maximum) {
    const double scale = static_cast<double>(maximum) / edge;
    transform.ScaledWidth(std::max(1u, static_cast<uint32_t>(decoder.PixelWidth() * scale)));
    transform.ScaledHeight(std::max(1u, static_cast<uint32_t>(decoder.PixelHeight() * scale)));
  }
  auto bitmap = decoder.GetSoftwareBitmapAsync(
      Graphics::Imaging::BitmapPixelFormat::Bgra8,
      Graphics::Imaging::BitmapAlphaMode::Ignore, transform,
      Graphics::Imaging::ExifOrientationMode::RespectExifOrientation,
      Graphics::Imaging::ColorManagementMode::DoNotColorManage).get();
  auto read = engine.RecognizeAsync(bitmap).get();
  flutter::EncodableList lines;
  for (const auto& line : read.Lines()) {
    double left = bitmap.PixelWidth(), top = bitmap.PixelHeight();
    double right = 0, bottom = 0;
    for (const auto& word : line.Words()) {
      const auto box = word.BoundingRect();
      left = std::min(left, static_cast<double>(box.X));
      top = std::min(top, static_cast<double>(box.Y));
      right = std::max(right, static_cast<double>(box.X + box.Width));
      bottom = std::max(bottom, static_cast<double>(box.Y + box.Height));
    }
    if (bottom > top) lines.emplace_back(Map{
        {Value("text"), Value(winrt::to_string(line.Text()))},
        {Value("left"), Value(left)}, {Value("top"), Value(top)},
        {Value("right"), Value(right)}, {Value("bottom"), Value(bottom)},
        {Value("angle"), Value(read.TextAngle() ? read.TextAngle().Value() : 0.0)}});
  }
  bitmap.Close(); stream.Close();
  // Windows OCR does not expose recognition confidence.
  return Value(Map{{Value("text"), Value(winrt::to_string(read.Text()))},
                   {Value("confidence"), Value()}, {Value("lines"), Value(lines)}});
}
}  // namespace

MediaImport::MediaImport(HWND window, flutter::BinaryMessenger* messenger)
    : window_(window) {
  audio_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "ondevice_llm/audio", &flutter::StandardMethodCodec::GetInstance());
  ocr_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "ondevice_llm/ocr", &flutter::StandardMethodCodec::GetInstance());
  audio_->SetMethodCallHandler([this](const auto& call, auto result) {
    Enqueue(true, call, std::move(result));
  });
  ocr_->SetMethodCallHandler([this](const auto& call, auto result) {
    Enqueue(false, call, std::move(result));
  });
  worker_ = std::thread([this] { Run(); });
}
MediaImport::~MediaImport() {
  audio_->SetMethodCallHandler(nullptr); ocr_->SetMethodCallHandler(nullptr);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopping_ = true;
    for (const auto& entry : cancellations_) *entry.second = true;
  }
  ready_.notify_one(); worker_.join();
}
void MediaImport::Enqueue(bool audio, const flutter::MethodCall<Value>& call,
                          std::unique_ptr<Result> result) {
  const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
  if (audio && call.method_name() == "cancel") {
    if (args) {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = cancellations_.find(StringArg(*args, "id"));
      if (it != cancellations_.end()) *it->second = true;
    }
    result->Success(); return;
  }
  if (call.method_name() != (audio ? "decode16k" : "recognize")) {
    result->NotImplemented(); return;
  }
  if (!args || StringArg(*args, "path").empty() ||
      (audio && StringArg(*args, "out").empty())) {
    result->Error(audio ? "audio" : "ocr", "Missing path."); return;
  }
  auto job = std::make_unique<Job>();
  job->audio = audio; job->path = StringArg(*args, "path");
  job->out = StringArg(*args, "out"); job->id = StringArg(*args, "id");
  if (job->id.empty()) job->id = job->out;
  const auto limit = args->find(Value("maxSeconds"));
  if (limit != args->end()) {
    if (const auto* value = std::get_if<int32_t>(&limit->second))
      job->limit = std::clamp(*value, 1, 3600);
  }
  job->cancelled = std::make_shared<std::atomic_bool>(false);
  job->result = std::move(result);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (audio && cancellations_.count(job->id)) {
      job->result->Error("audio", "Recording import is already running."); return;
    }
    if (audio) cancellations_[job->id] = job->cancelled;
    pending_.push_back(std::move(job));
  }
  ready_.notify_one();
}
void MediaImport::Run() {
  // MTA permits blocking waits on WinRT async operations on this worker.
  const HRESULT apartment = RoInitialize(RO_INIT_MULTITHREADED);
  for (;;) {
    std::unique_ptr<Job> job;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      ready_.wait(lock, [this] { return stopping_ || !pending_.empty(); });
      if (stopping_) break;
      job = std::move(pending_.front()); pending_.pop_front();
    }
    try {
      Check(apartment);
      job->value = job->audio
          ? Decode(job->path, job->out, job->limit, *job->cancelled)
          : Recognize(job->path);
    } catch (const winrt::hresult_error& error) {
      job->error = winrt::to_string(error.message());
    } catch (const std::exception& error) { job->error = error.what(); }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (job->audio) cancellations_.erase(job->id);
      completed_.push_back(std::move(job));
    }
    PostMessage(window_, kMediaComplete, 0, 0);
  }
  if (SUCCEEDED(apartment)) RoUninitialize();
}
bool MediaImport::HandleMessage(UINT message) {
  if (message != kMediaComplete) return false;
  std::deque<std::unique_ptr<Job>> completed;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    completed.swap(completed_);
  }
  for (auto& job : completed) {
    if (job->error.empty()) job->result->Success(job->value);
    else job->result->Error(job->audio ? "audio" :
        (job->error.find("OCR unavailable.") == 0 ? "ocr_unavailable" : "ocr"),
        job->error);
  }
  return true;
}
