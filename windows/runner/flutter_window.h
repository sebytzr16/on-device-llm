#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"
#include "tray_icon.h"
#include "voice_audio.h"
#include "media_import.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  FlutterWindow(const flutter::DartProject& project,
                const std::vector<std::string>& args);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;
  flutter::EncodableList pending_args_;
  bool args_ready_ = false;
  bool display_ready_ = false;
  int last_refresh_rate_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> desktop_channel_;

  std::unique_ptr<TrayIcon> tray_;
  std::unique_ptr<VoiceAudio> voice_audio_;
  std::unique_ptr<MediaImport> media_import_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
