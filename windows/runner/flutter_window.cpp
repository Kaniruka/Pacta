#include "flutter_window.h"

#include <algorithm>
#include <optional>
#include <string>
#include <utility>
#include <variant>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kOpenWindowCommand = 4201;
constexpr UINT kExitAppCommand = 4202;
constexpr UINT_PTR kTrayCleanupTimerId = 4203;
constexpr UINT kTrayCleanupDelayMs = 12000;

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return L"";
  const int required = MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1,
                                           nullptr, 0);
  if (required <= 1) return L"";
  std::wstring result(static_cast<size_t>(required), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(), -1, result.data(), required);
  result.pop_back();
  return result;
}

const flutter::EncodableValue* FindValue(
    const flutter::EncodableMap* values,
    const char* key) {
  if (!values) return nullptr;
  const auto item = values->find(flutter::EncodableValue(key));
  return item == values->end() ? nullptr : &item->second;
}

std::wstring ReadWideString(const flutter::EncodableMap* values,
                            const char* key) {
  const auto* value = FindValue(values, key);
  const auto* string_value =
      value ? std::get_if<std::string>(value) : nullptr;
  return string_value ? Utf8ToWide(*string_value) : L"";
}

bool ReadBool(const flutter::EncodableMap* values,
              const char* key,
              bool default_value = false) {
  const auto* value = FindValue(values, key);
  const auto* bool_value = value ? std::get_if<bool>(value) : nullptr;
  return bool_value ? *bool_value : default_value;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  focus_status_channel_ = std::make_unique<
      flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "com.pacta/focus_status",
      &flutter::StandardMethodCodec::GetInstance());
  focus_status_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandleFocusStatusCall(call, std::move(result));
      });

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
  RemoveTrayIcon();
  focus_status_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kTrayCallbackMessage) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK ||
        lparam == NIN_SELECT) {
      RestoreWindow();
    } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      ShowTrayMenu();
    }
    return 0;
  }

  if (message == WM_COMMAND) {
    switch (LOWORD(wparam)) {
      case kOpenWindowCommand:
        RestoreWindow();
        return 0;
      case kExitAppCommand:
        background_running_enabled_ = false;
        focus_status_active_ = false;
        Destroy();
        return 0;
    }
  }

  if (message == WM_CLOSE && background_running_enabled_ &&
      focus_status_active_) {
    window_hidden_ = true;
    ShowWindow(hwnd, SW_HIDE);
    return 0;
  }

  if (message == WM_TIMER && wparam == kTrayCleanupTimerId) {
    KillTimer(hwnd, kTrayCleanupTimerId);
    notification_cleanup_pending_ = false;
    if (!focus_status_active_ && !background_running_enabled_ &&
        !window_hidden_) {
      RemoveTrayIcon();
    }
    return 0;
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

void FlutterWindow::HandleFocusStatusCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* arguments =
      std::get_if<flutter::EncodableMap>(call.arguments());
  if (call.method_name() == "setBackgroundRunningEnabled") {
    const auto* enabled =
        std::get_if<bool>(call.arguments());
    background_running_enabled_ = enabled && *enabled;
    if (!background_running_enabled_ && !focus_status_active_ &&
        !window_hidden_ && !notification_cleanup_pending_) {
      RemoveTrayIcon();
    }
    result->Success();
    return;
  }

  if (call.method_name() == "updateStatus") {
    focus_status_text_ = ReadWideString(arguments, "text");
    focus_status_active_ = ReadBool(arguments, "active");
    if (focus_status_active_) {
      if (!UpdateTrayTooltip(focus_status_text_)) {
        result->Error("tray_status_failed",
                      "Windows could not update the Pacta tray status.");
        return;
      }
    } else {
      UpdateTrayTooltip(L"Pacta");
      if (!background_running_enabled_ && !window_hidden_ &&
          !notification_cleanup_pending_) {
        RemoveTrayIcon();
      }
    }
    result->Success();
    return;
  }

  if (call.method_name() == "showNotification") {
    const std::wstring title = ReadWideString(arguments, "title");
    const std::wstring body = ReadWideString(arguments, "body");
    EnsureTrayIcon();
    tray_icon_data_.uFlags = NIF_INFO;
    wcsncpy_s(tray_icon_data_.szInfoTitle, title.c_str(), _TRUNCATE);
    wcsncpy_s(tray_icon_data_.szInfo, body.c_str(), _TRUNCATE);
    tray_icon_data_.dwInfoFlags = NIIF_INFO;
    if (!Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_)) {
      result->Error("tray_notification_failed",
                    "Windows could not display the Pacta tray notification.");
      return;
    }
    notification_cleanup_pending_ = true;
    SetTimer(GetHandle(), kTrayCleanupTimerId, kTrayCleanupDelayMs, nullptr);
    result->Success();
    return;
  }

  if (call.method_name() == "clearStatus") {
    focus_status_active_ = false;
    focus_status_text_.clear();
    UpdateTrayTooltip(L"Pacta");
    if (!background_running_enabled_ && !window_hidden_ &&
        !notification_cleanup_pending_) {
      RemoveTrayIcon();
    }
    result->Success();
    return;
  }

  result->NotImplemented();
}

bool FlutterWindow::EnsureTrayIcon() {
  if (tray_icon_added_) return true;
  if (GetHandle() == nullptr) return false;
  tray_icon_data_ = {};
  tray_icon_data_.cbSize = sizeof(NOTIFYICONDATAW);
  tray_icon_data_.hWnd = GetHandle();
  tray_icon_data_.uID = kTrayIconId;
  tray_icon_data_.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  tray_icon_data_.uCallbackMessage = kTrayCallbackMessage;
  tray_icon_data_.hIcon = LoadIcon(GetModuleHandle(nullptr),
                                   MAKEINTRESOURCE(IDI_APP_ICON));
  wcsncpy_s(tray_icon_data_.szTip, L"Pacta", _TRUNCATE);
  tray_icon_added_ = Shell_NotifyIconW(NIM_ADD, &tray_icon_data_) != FALSE;
  return tray_icon_added_;
}

void FlutterWindow::RemoveTrayIcon() {
  if (!tray_icon_added_) return;
  KillTimer(GetHandle(), kTrayCleanupTimerId);
  notification_cleanup_pending_ = false;
  Shell_NotifyIconW(NIM_DELETE, &tray_icon_data_);
  tray_icon_added_ = false;
}

bool FlutterWindow::UpdateTrayTooltip(const std::wstring& text) {
  if (!EnsureTrayIcon()) return false;
  const std::wstring tooltip = text.empty() ? L"Pacta" : text;
  wcsncpy_s(tray_icon_data_.szTip, tooltip.c_str(), _TRUNCATE);
  tray_icon_data_.uFlags = NIF_TIP;
  return Shell_NotifyIconW(NIM_MODIFY, &tray_icon_data_) != FALSE;
}

void FlutterWindow::ShowTrayMenu() {
  EnsureTrayIcon();
  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(GetHandle());
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  const std::wstring status = focus_status_text_.empty()
                                  ? L"Pacta"
                                  : focus_status_text_;
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 0, status.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kOpenWindowCommand, L"Open Pacta");
  AppendMenuW(menu, MF_STRING, kExitAppCommand, L"Exit Pacta");
  TrackPopupMenu(menu, TPM_RIGHTBUTTON | TPM_BOTTOMALIGN, cursor.x, cursor.y, 0,
                 GetHandle(), nullptr);
  DestroyMenu(menu);
}

void FlutterWindow::RestoreWindow() {
  window_hidden_ = false;
  ShowWindow(GetHandle(), SW_RESTORE);
  SetForegroundWindow(GetHandle());
}
