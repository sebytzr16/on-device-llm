#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>
#include "utils.h"

#include "flutter/generated_plugin_registrant.h"

namespace {
int RefreshRateForWindow(HWND hwnd) {
  MONITORINFOEXW monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST),
                       &monitor)) return 0;
  DEVMODEW mode{};
  mode.dmSize = sizeof(mode);
  if (!EnumDisplaySettingsW(monitor.szDevice, ENUM_CURRENT_SETTINGS, &mode))
    return 0;
  return mode.dmDisplayFrequency > 1 ? mode.dmDisplayFrequency : 0;
}
constexpr UINT_PTR kDisplaySettledTimer = 0x484a;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             const std::vector<std::string>& args)
    : project_(project) {
  for (const auto& arg : args) pending_args_.emplace_back(arg);
}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  media_import_ = std::make_unique<MediaImport>(
      GetHandle(), flutter_controller_->engine()->messenger());
  voice_audio_ = std::make_unique<VoiceAudio>(
      GetHandle(), flutter_controller_->engine()->messenger());
  desktop_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "ondevice_llm/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "getInitialArgs") {
          args_ready_ = true;
          result->Success(flutter::EncodableValue(pending_args_));
          pending_args_.clear();
        } else if (call.method_name() == "refreshRate") {
          display_ready_ = true;
          last_refresh_rate_ = RefreshRateForWindow(GetHandle());
          result->Success(flutter::EncodableValue(last_refresh_rate_));
        } else if (call.method_name() == "availableBytes") {
          const auto* path = call.arguments()
              ? std::get_if<std::string>(call.arguments()) : nullptr;
          ULARGE_INTEGER available{};
          if (path && GetDiskFreeSpaceExW(Utf8ToWide(*path).c_str(), &available,
                                         nullptr, nullptr)) {
            result->Success(flutter::EncodableValue(
                static_cast<int64_t>(available.QuadPart)));
          } else {
            result->Error("storage", "Cannot query destination volume");
          }
        } else {
          result->NotImplemented();
        }
      });
  tray_ = std::make_unique<TrayIcon>(
      flutter_controller_->engine()->messenger(), GetHandle());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  media_import_.reset();
  voice_audio_.reset();
  tray_.reset();
  desktop_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (tray_ && tray_->HandleMessage(message, lparam)) return 0;
  if (media_import_ && media_import_->HandleMessage(message)) return 0;
  if (voice_audio_ && voice_audio_->HandleMessage(message, wparam, lparam))
    return 0;
  // A shutdown, logoff or the installer's Restart Manager sends no
  // WM_CLOSE, so placement is also saved then and once a move or maximize
  // settles (P3-32).
  if (message == WM_CLOSE || (message == WM_ENDSESSION && wparam)) {
    SavePlacement();
  }
  if (message == WM_MOVE || message == WM_DPICHANGED ||
      message == WM_DISPLAYCHANGE || message == WM_EXITSIZEMOVE ||
      (message == WM_SIZE &&
       (wparam == SIZE_MAXIMIZED || wparam == SIZE_RESTORED))) {
    SetTimer(hwnd, kDisplaySettledTimer, 150, nullptr);
  }
  if (message == WM_TIMER && wparam == kDisplaySettledTimer) {
    KillTimer(hwnd, kDisplaySettledTimer);
    if (IsWindowVisible(hwnd) && !IsIconic(hwnd)) SavePlacement();
    const int rate = RefreshRateForWindow(hwnd);
    if (display_ready_ && desktop_channel_ && rate != last_refresh_rate_) {
      last_refresh_rate_ = rate;
      desktop_channel_->InvokeMethod("refreshRateChanged",
          std::make_unique<flutter::EncodableValue>(rate));
    }
    return 0;
  }
  if (message == WM_COPYDATA) {
    const auto* data = reinterpret_cast<const COPYDATASTRUCT*>(lparam);
    if (!data || data->dwData != 0x4f444c4c || data->cbData > 1024 * 1024 ||
        (data->cbData && !data->lpData)) return FALSE;
    flutter::EncodableList args;
    const auto* bytes = static_cast<const char*>(data->lpData);
    size_t start = 0;
    for (size_t i = 0; i < data->cbData; ++i) {
      if (bytes[i] == '\0') {
        args.emplace_back(std::string(bytes + start, i - start));
        start = i + 1;
      }
    }
    if (start != data->cbData) return FALSE;
    if (args_ready_ && desktop_channel_) {
      desktop_channel_->InvokeMethod("launchArgs",
          std::make_unique<flutter::EncodableValue>(args));
    } else {
      pending_args_.insert(pending_args_.end(), args.begin(), args.end());
    }
    ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
    SetForegroundWindow(hwnd);
    return TRUE;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
