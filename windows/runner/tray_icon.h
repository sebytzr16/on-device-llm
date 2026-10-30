#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>
#include <shellapi.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <map>
#include "resource.h"
#include "utils.h"

#pragma comment(lib, "shell32.lib")

class TrayIcon {
 public:
  TrayIcon(flutter::BinaryMessenger* messenger, HWND window)
      : window_(window), channel_(messenger, "ondevice_llm/tray",
                                &flutter::StandardMethodCodec::GetInstance()) {
    taskbar_created_ = RegisterWindowMessageW(L"TaskbarCreated");
    data_.cbSize = sizeof(data_);
    data_.hWnd = window;
    data_.uID = 1;
    data_.uCallbackMessage = WM_APP + 41;
    data_.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      if (call.method_name() == "update") {
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (!args) {
          result->Error("arguments", "Expected tray configuration");
          return;
        }
        const auto& visible = Value(*args, "visible");
        const bool show = std::get_if<bool>(&visible) && std::get<bool>(visible);
        const auto* tooltip = std::get_if<std::string>(&Value(*args, "tooltip"));
        const auto* items = std::get_if<flutter::EncodableList>(&Value(*args, "items"));
        if (tooltip) Copy(data_.szTip, Utf8ToWide(*tooltip));
        if (items) items_ = *items;
        if (show) {
          data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
          if (!Shell_NotifyIconW(visible_ ? NIM_MODIFY : NIM_ADD, &data_)) {
            result->Error("tray", "Cannot add notification icon");
            return;
          }
          visible_ = true;
        } else {
          Remove();
        }
        result->Success();
      } else if (call.method_name() == "balloon") {
        const auto* text = call.arguments()
            ? std::get_if<std::string>(call.arguments()) : nullptr;
        if (text && visible_) {
          data_.uFlags = NIF_INFO;
          Copy(data_.szInfo, Utf8ToWide(*text));
          Copy(data_.szInfoTitle, std::wstring(data_.szTip));
          data_.dwInfoFlags = NIIF_INFO;
          Shell_NotifyIconW(NIM_MODIFY, &data_);
        }
        result->Success();
      } else {
        result->NotImplemented();
      }
    });
  }

  ~TrayIcon() { Remove(); }

  bool HandleMessage(UINT message, LPARAM lparam) {
    if (taskbar_created_ && message == taskbar_created_ && visible_) {
      data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
      Shell_NotifyIconW(NIM_ADD, &data_);
      return true;
    }
    if (message != WM_APP + 41) return false;
    if (lparam == WM_LBUTTONUP) {
      ShowWindow(window_, IsIconic(window_) ? SW_RESTORE : SW_SHOW);
      SetForegroundWindow(window_);
      channel_.InvokeMethod("selected", std::make_unique<flutter::EncodableValue>("open"));
    } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      std::map<UINT, std::string> ids;
      UINT next = 1;
      HMENU menu = BuildMenu(items_, ids, next);
      POINT point{};
      GetCursorPos(&point);
      SetForegroundWindow(window_);
      const UINT chosen = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
          point.x, point.y, 0, window_, nullptr);
      DestroyMenu(menu);
      PostMessageW(window_, WM_NULL, 0, 0);
      const auto it = ids.find(chosen);
      if (it != ids.end()) {
        channel_.InvokeMethod("selected",
            std::make_unique<flutter::EncodableValue>(it->second));
      }
    }
    return true;
  }

 private:
  static const flutter::EncodableValue& Value(
      const flutter::EncodableMap& map, const char* key) {
    static const flutter::EncodableValue empty;
    const auto it = map.find(flutter::EncodableValue(key));
    return it == map.end() ? empty : it->second;
  }

  template <size_t N>
  static void Copy(wchar_t (&target)[N], const std::wstring& text) {
    wcsncpy_s(target, text.c_str(), _TRUNCATE);
  }

  static HMENU BuildMenu(const flutter::EncodableList& items,
                         std::map<UINT, std::string>& ids, UINT& next) {
    HMENU menu = CreatePopupMenu();
    for (const auto& item : items) {
      const auto* map = std::get_if<flutter::EncodableMap>(&item);
      if (!map) continue;
      const auto* label = std::get_if<std::string>(&Value(*map, "label"));
      const auto* id = std::get_if<std::string>(&Value(*map, "id"));
      if (!label || !id) continue;
      UINT flags = MF_STRING;
      if (Value(*map, "enabled") == flutter::EncodableValue(false)) flags |= MF_GRAYED;
      if (Value(*map, "checked") == flutter::EncodableValue(true)) flags |= MF_CHECKED;
      const auto* children = std::get_if<flutter::EncodableList>(&Value(*map, "children"));
      // Labels are data; ampersands in model names must not become mnemonics.
      std::wstring text = Utf8ToWide(*label);
      size_t offset = 0;
      while ((offset = text.find(L'&', offset)) != std::wstring::npos) {
        text.insert(offset, 1, L'&');
        offset += 2;
      }
      if (children) {
        AppendMenuW(menu, flags | MF_POPUP,
            reinterpret_cast<UINT_PTR>(BuildMenu(*children, ids, next)), text.c_str());
      } else {
        ids.emplace(next, *id);
        AppendMenuW(menu, flags, next++, text.c_str());
      }
    }
    return menu;
  }

  void Remove() {
    if (visible_) Shell_NotifyIconW(NIM_DELETE, &data_);
    visible_ = false;
  }

  HWND window_;
  UINT taskbar_created_ = 0;
  bool visible_ = false;
  NOTIFYICONDATAW data_{};
  flutter::EncodableList items_;
  flutter::MethodChannel<flutter::EncodableValue> channel_;
};

#endif  // RUNNER_TRAY_ICON_H_
