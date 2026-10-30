#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE mutex = CreateMutex(nullptr, FALSE, L"Local\\OnDeviceLLM.Desktop");
  if (!mutex) return EXIT_FAILURE;
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    bool delivered = false;
    HWND existing = nullptr;
    // The first process may still be creating its Flutter engine.
    for (int attempt = 0; attempt < 200 && !existing; ++attempt) {
      existing = FindWindow(L"OnDeviceLLM.Desktop.Window", nullptr);
      if (!existing) Sleep(50);
    }
    if (existing) {
      DWORD process = 0;
      GetWindowThreadProcessId(existing, &process);
      AllowSetForegroundWindow(process);
      std::string payload;
      for (const auto& arg : GetCommandLineArguments()) {
        payload.append(arg).push_back('\0');
      }
      COPYDATASTRUCT data{0x4f444c4c, static_cast<DWORD>(payload.size()),
                          payload.empty() ? nullptr : payload.data()};
      DWORD_PTR result = 0;
      delivered = SendMessageTimeout(existing, WM_COPYDATA, 0,
                         reinterpret_cast<LPARAM>(&data), SMTO_ABORTIFHUNG,
                         10000, &result) != 0 && result == TRUE;
      if (IsIconic(existing)) ShowWindow(existing, SW_RESTORE);
      SetForegroundWindow(existing);
    }
    CloseHandle(mutex);
    return delivered ? EXIT_SUCCESS : EXIT_FAILURE;
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(command_line_arguments);

  FlutterWindow window(project, command_line_arguments);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(L"OnDevice LLM", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  CloseHandle(mutex);
  return EXIT_SUCCESS;
}
