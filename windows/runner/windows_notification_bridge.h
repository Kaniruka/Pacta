#ifndef RUNNER_WINDOWS_NOTIFICATION_BRIDGE_H_
#define RUNNER_WINDOWS_NOTIFICATION_BRIDGE_H_

#include <windows.h>

#include <cstdint>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace pacta {

// Posted by the bridge to the window once an activation is queued. Only the
// window procedure may call into Dart, so every activation travels through this
// message instead of the SDK's COM worker thread.
constexpr UINT kNotificationActivationMessage = WM_APP + 2;

// Product Windows notification identity.
//
// The AppUserModelId is a stable distribution concern: reminders registered by
// one build must stay clickable after an upgrade, so the identity never carries
// a build number. The SDK owns the activator GUID; this bridge never writes one.
constexpr wchar_t kProductAppUserModelId[] = L"Pacta.Desktop.Focus";
constexpr wchar_t kTestAppUserModelIdPrefix[] = L"Pacta.Test.";

// Owns the Windows App SDK registration and the scheduled toast queue for the
// current process.
//
// Registration is process-wide and one-shot: SetCurrentProcessExplicitAppUserModelID
// must run before the first AppNotificationManager::Default(), and the SDK keeps
// the registered identity for the rest of the process. Every method that touches
// WinRT runs on the platform thread; only the SDK callback is invoked from a COM
// worker thread, and it only appends to an owned queue.
class WindowsNotificationBridge {
 public:
  WindowsNotificationBridge();
  ~WindowsNotificationBridge();

  WindowsNotificationBridge(const WindowsNotificationBridge&) = delete;
  WindowsNotificationBridge& operator=(const WindowsNotificationBridge&) = delete;

  // Registers this process once. Returns false with a stable |error_code| when
  // the SDK is unavailable, the identity is rejected, or Register fails; the
  // process then keeps the in-process tray surface only.
  bool Start(std::string* error_code, std::string* error_message,
             int32_t* error_hresult);

  // Stops activation intake, revokes the handler and calls the *public*
  // Unregister, which keeps already scheduled reminders queued in the OS. A
  // normal window/process exit must go through this path.
  void Stop();

  bool registered() const { return registered_; }
  const std::wstring& app_user_model_id() const { return aumid_; }
  std::string identity_source() const { return identity_source_; }

  // Platform-thread plumbing.
  void AttachWindow(HWND window,
                    std::function<void(const std::string&)> emit_click);
  void DetachWindow();
  void SetDartReady(bool ready);
  void DrainPendingActivations();

  // Schedules one one-shot reminder. |due_unix_ms| is converted with the proven
  // 100 ns FILETIME contract and rejected when it is in the past or overflows.
  bool Schedule(int64_t id, const std::wstring& title,
                const std::wstring& body, int64_t due_unix_ms,
                const std::wstring& payload, std::string* error_code,
                std::string* error_message, int32_t* error_hresult);

  bool Cancel(int64_t id, std::string* error_code, std::string* error_message,
              int32_t* error_hresult);

  bool PendingIds(std::vector<int64_t>* ids, std::string* error_code,
                  std::string* error_message, int32_t* error_hresult);

  // Read-only view of the OS notification switch. Never writes a setting.
  bool NotificationsEnabled(bool* enabled);

  // Fixture-only: permanently removes the SDK registration for a Pacta.Test.*
  // identity. Refused for the product identity and for release builds.
  bool UnregisterAllForTestIdentity(std::string* error_code,
                                    std::string* error_message,
                                    int32_t* error_hresult);

  // Called from the SDK's COM worker thread with the raw activation argument.
  void OnNotificationInvoked(const std::wstring& argument) noexcept;

 private:
  void EnqueueActivation(const std::string& payload);
  void RecordError(const std::string& code, const std::string& message,
                   int32_t hresult, std::string* error_code,
                   std::string* error_message, int32_t* error_hresult);

  std::wstring aumid_;
  std::string identity_source_ = "none";
  bool registered_ = false;
  bool stopping_ = false;
  bool dart_ready_ = false;
  bool handler_attached_ = false;
  int64_t handler_token_ = 0;

  // Opaque SDK manager pointer; the concrete WinRT type stays in the .cpp so
  // this header never drags C++/WinRT headers into the Flutter runner.
  void* manager_ = nullptr;

  HWND window_ = nullptr;
  std::function<void(const std::string&)> emit_click_;

  std::mutex queue_mutex_;
  std::deque<std::string> pending_activations_;
};

}  // namespace pacta

#endif  // RUNNER_WINDOWS_NOTIFICATION_BRIDGE_H_
