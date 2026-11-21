#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>
#include <algorithm>
#include <cwctype>
#include <string>

#include "bridge_smoke_exports.h"

#include "flutter_window.h"
#include "utils.h"

namespace {
// stdout is inherited as a pipe by Process.start, even for this GUI executable.
int SmokeResult(bool ok) {
  const std::string json = ok ? "{\"ok\":true}\n" : "{\"ok\":false}\n";
  DWORD written = 0;
  WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), json.data(),
            static_cast<DWORD>(json.size()), &written, nullptr);
  return ok ? EXIT_SUCCESS : EXIT_FAILURE;
}

int SmokeBridge(int argc, wchar_t** argv) {
  SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX |
               SEM_NOOPENFILEERRORBOX);
  if (argc < 3) return SmokeResult(false);
  for (int index = 2; index < argc; ++index) {
    const std::wstring path(argv[index]);
    const auto slash = path.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return SmokeResult(false);
    // Pack staging is writable, so dependencies must come from trusted paths.
    HMODULE library = LoadLibraryExW(
        path.c_str(), nullptr,
        LOAD_LIBRARY_SEARCH_APPLICATION_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    bool ok = library != nullptr;
    if (library) {
      for (const auto symbol : kBridgeSmokeExports) {
        if (!GetProcAddress(library, symbol)) ok = false;
      }
      auto file = path.substr(slash + 1);
      std::transform(file.begin(), file.end(), file.begin(),
                     [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
      if (ok && (file.find(L"_cuda") != std::wstring::npos ||
                 file.find(L"_vulkan") != std::wstring::npos)) {
        using DeviceCount = int(__cdecl*)();
        const auto count = reinterpret_cast<DeviceCount>(
            GetProcAddress(library, "od_gpu_device_count"));
        ok = count() > 0;
      }
      FreeLibrary(library);
    }
    if (!ok) return SmokeResult(false);
  }
  return SmokeResult(true);
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Drop the current directory from the DLL search order. Not
  // SetDefaultDllDirectories: Dart's DynamicLibrary.open passes
  // LOAD_WITH_ALTERED_SEARCH_PATH, which then fails with error 87 and the app
  // cannot open sqlite3mc.dll. Pack bridges use restricted flags per load.
  if (!SetDllDirectoryW(L"")) return EXIT_FAILURE;
  int argc = 0;
  wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
  if (argv && argc > 1 && std::wstring(argv[1]) == L"--engine-smoke") {
    const int result = SmokeBridge(argc, argv);
    LocalFree(argv);
    return result;
  }
  if (argv) LocalFree(argv);
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
