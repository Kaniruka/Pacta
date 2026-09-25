#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <flutter/flutter_view_controller.h>
#include <shellapi.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  bool EnsureTrayIcon();
  void RemoveTrayIcon();
  bool UpdateTrayTooltip(const std::wstring& text);
  void ShowTrayMenu();
  void RestoreWindow();
  void HandleFocusStatusCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<
      flutter::MethodChannel<flutter::EncodableValue>> focus_status_channel_;
  NOTIFYICONDATAW tray_icon_data_{};
  bool tray_icon_added_ = false;
  bool background_running_enabled_ = false;
  bool focus_status_active_ = false;
  bool window_hidden_ = false;
  bool notification_cleanup_pending_ = false;
  std::wstring focus_status_text_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
