#ifndef RUNNER_MEDIA_IMPORT_H_
#define RUNNER_MEDIA_IMPORT_H_

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <atomic>
#include <condition_variable>
#include <deque>
#include <map>
#include <memory>
#include <mutex>
#include <thread>

// Serial worker keeps platform decoding off Flutter's thread. Replies are
// delivered on the window thread, and shutdown joins before the engine dies.
class MediaImport {
 public:
  MediaImport(HWND window, flutter::BinaryMessenger* messenger);
  ~MediaImport();
  bool HandleMessage(UINT message);
 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  struct Job {
    bool audio;
    std::string path, out, id;
    int limit = 3600;
    std::shared_ptr<std::atomic_bool> cancelled;
    std::unique_ptr<Result> result;
    Value value;
    std::string error;
  };
  void Enqueue(bool audio, const flutter::MethodCall<Value>& call,
               std::unique_ptr<Result> result);
  void Run();
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<Value>> audio_, ocr_;
  std::mutex mutex_;
  std::condition_variable ready_;
  bool stopping_ = false;
  std::deque<std::unique_ptr<Job>> pending_, completed_;
  std::map<std::string, std::shared_ptr<std::atomic_bool>> cancellations_;
  std::thread worker_;
};
#endif
