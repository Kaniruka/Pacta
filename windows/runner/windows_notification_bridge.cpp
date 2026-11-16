#include "windows_notification_bridge.h"

#include <winrt/base.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Microsoft.Windows.AppNotifications.h>
#include <winrt/Windows.Foundation.Collections.h>

#include <shobjidl.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cwchar>
#include <memory>
#include <optional>
#include <utility>

namespace pacta {
namespace {

namespace ANA = winrt::Microsoft::Windows::AppNotifications;
namespace WF = winrt::Windows::Foundation;
namespace WDN = winrt::Windows::Data::Xml::Dom;
namespace WUN = winrt::Windows::UI::Notifications;

using winrt::hstring;

// FILETIME / WinRT DateTime contract, verified by the R5 probe:
// DateTime::period == ratio<1, 10'000'000>, rep == int64_t, epoch 1601-01-01 UTC.
constexpr int64_t kTicksPerMillisecond = 10000;
constexpr int64_t kFileTimeEpochOffsetTicks = 116444736000000000LL;  // 1970-01-01 UTC
constexpr size_t kMaxAumidLength = 128;
constexpr wchar_t kScheduledTag[] = L"pacta";
constexpr wchar_t kScheduledGroup[] = L"pacta";
constexpr size_t kMaxScheduledIdDigits = 16;

// Fixture override file, written by the schedule-reminder fixture before launch.
// Only a build configured with PACTA_NOTIFICATION_FIXTURE reads it, every value
// must stay inside the Pacta.Test.* identity space, and the file never touches
// the product identity.
#if defined(PACTA_NOTIFICATION_FIXTURE)
constexpr bool kFixtureBuild = true;
#else
constexpr bool kFixtureBuild = false;
#endif
constexpr wchar_t kFixtureIdentityFileName[] = L"pacta_fixture_identity.json";

constexpr const wchar_t* kPayloadPrefixes[] = {
    L"schedule-reminder:", L"plan-day:", L"plan-item:",
    L"daily-open-reminder:", L"national-focus-reminder:", L"session:",
    L"appointment:",
};

std::string ToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int required = ::WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                             static_cast<int>(value.size()),
                                             nullptr, 0, nullptr, nullptr);
  if (required <= 0) return {};
  std::string out(static_cast<size_t>(required), '\0');
  ::WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        out.data(), required, nullptr, nullptr);
  return out;
}

std::wstring ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int required = ::MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                             static_cast<int>(value.size()), nullptr, 0);
  if (required <= 0) return {};
  std::wstring out(static_cast<size_t>(required), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        out.data(), required);
  return out;
}

std::wstring ExecutableDirectory() {
  std::wstring path(MAX_PATH, L'\0');
  for (;;) {
    const DWORD written = ::GetModuleFileNameW(nullptr, path.data(),
                                               static_cast<DWORD>(path.size()));
    if (written == 0) return {};
    if (static_cast<size_t>(written) < path.size()) {
      path.resize(static_cast<size_t>(written));
      break;
    }
    path.resize(path.size() * 2);
  }
  const size_t separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return {};
  return path.substr(0, separator);
}

// Minimal string-field reader for the fixture identity file. The fixture owns
// that file, so a full JSON parser would be dead weight in the runner.
std::optional<std::wstring> ReadJsonStringField(const std::string& json,
                                                const char* field) {
  const std::string needle = std::string("\"") + field + "\"";
  size_t cursor = json.find(needle);
  if (cursor == std::string::npos) return std::nullopt;
  cursor = json.find(':', cursor + needle.size());
  if (cursor == std::string::npos) return std::nullopt;
  ++cursor;
  while (cursor < json.size() &&
         (json[cursor] == ' ' || json[cursor] == '\t' || json[cursor] == '\n' ||
          json[cursor] == '\r')) {
    ++cursor;
  }
  if (cursor >= json.size() || json[cursor] != '"') return std::nullopt;
  ++cursor;
  std::string raw;
  bool escaped = false;
  for (; cursor < json.size(); ++cursor) {
    const char c = json[cursor];
    if (escaped) {
      raw.push_back('\\');
      raw.push_back(c);
      escaped = false;
      continue;
    }
    if (c == '\\') {
      escaped = true;
      continue;
    }
    if (c == '"') break;
    raw.push_back(c);
  }
  if (cursor >= json.size()) return std::nullopt;
  return ToWide(raw);
}

std::optional<std::wstring> ReadFixtureAppUserModelId() {
  const std::wstring directory = ExecutableDirectory();
  if (directory.empty()) return std::nullopt;
  const std::wstring path = directory + L"\\" + kFixtureIdentityFileName;
  const HANDLE file = ::CreateFileW(path.c_str(), GENERIC_READ,
                                    FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                                    OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) return std::nullopt;
  std::string contents;
  std::array<char, 4096> buffer{};
  DWORD read = 0;
  while (::ReadFile(file, buffer.data(), static_cast<DWORD>(buffer.size()),
                    &read, nullptr) &&
         read > 0) {
    contents.append(buffer.data(), static_cast<size_t>(read));
  }
  ::CloseHandle(file);
  if (contents.empty()) return std::nullopt;
  return ReadJsonStringField(contents, "aumid");
}

bool IsTestIdentity(const std::wstring& aumid) {
  const size_t prefix_length = std::wcslen(kTestAppUserModelIdPrefix);
  return aumid.size() > prefix_length &&
         aumid.compare(0, prefix_length, kTestAppUserModelIdPrefix) == 0;
}

// A fixture run has to choose the identity before Dart starts, so it is passed
// in the environment. Only the Pacta.Test.* namespace is accepted: the product
// identity can never be replaced from outside the process.
std::optional<std::wstring> ReadEnvironmentTestAumid() {
  const DWORD required = ::GetEnvironmentVariableW(
      L"PACTA_TEST_NOTIFICATION_AUMID", nullptr, 0);
  if (required == 0) return std::nullopt;
  std::wstring value(static_cast<size_t>(required), L'\0');
  const DWORD written = ::GetEnvironmentVariableW(
      L"PACTA_TEST_NOTIFICATION_AUMID", value.data(), required);
  if (written == 0 || written >= required) return std::nullopt;
  value.resize(static_cast<size_t>(written));
  if (!IsTestIdentity(value) || value.size() > kMaxAumidLength) {
    return std::nullopt;
  }
  return value;
}

bool FixtureTeardownAllowed() {
  wchar_t value[8] = {};
  const DWORD written = ::GetEnvironmentVariableW(
      L"PACTA_NOTIFICATION_FIXTURE_ALLOW_UNREGISTER_ALL", value,
      static_cast<DWORD>(std::size(value)));
  return written == 1 && value[0] == L'1';
}

std::wstring ResolveAppUserModelId(std::string* source) {
  if (auto test_identity = ReadEnvironmentTestAumid(); test_identity) {
    *source = "environment";
    return *test_identity;
  }
  if constexpr (kFixtureBuild) {
    if (auto fixture = ReadFixtureAppUserModelId(); fixture) {
      if (IsTestIdentity(*fixture) && fixture->size() <= kMaxAumidLength) {
        *source = "fixture-file";
        return *fixture;
      }
      *source = "fixture-file-rejected";
    }
  }
  *source = kFixtureBuild ? "fixture-default" : "product";
  return kProductAppUserModelId;
}

bool UnixMsToFileTime(int64_t unix_ms, int64_t* out_ticks) {
  if (out_ticks == nullptr) return false;
  if (unix_ms <= 0) return false;
  if (unix_ms > (INT64_MAX - kFileTimeEpochOffsetTicks) / kTicksPerMillisecond) {
    return false;
  }
  *out_ticks = kFileTimeEpochOffsetTicks + unix_ms * kTicksPerMillisecond;
  return true;
}

int64_t NowFileTimeTicks() {
  FILETIME now{};
  ::GetSystemTimeAsFileTime(&now);
  ULARGE_INTEGER value{};
  value.LowPart = now.dwLowDateTime;
  value.HighPart = now.dwHighDateTime;
  return static_cast<int64_t>(value.QuadPart);
}

// The SDK hands back whatever argument the notification carried. An unpackaged
// activation may wrap it in its own JSON envelope, so the payload is located by
// its own prefix and, when the argument is JSON, unescaped exactly once.
bool ExtractPayload(const std::wstring& argument, std::wstring* payload) {
  if (payload == nullptr || argument.empty()) return false;
  size_t best = std::wstring::npos;
  for (const wchar_t* prefix : kPayloadPrefixes) {
    const size_t found = argument.find(prefix);
    if (found != std::wstring::npos && (best == std::wstring::npos || found < best)) {
      best = found;
    }
  }
  if (best == std::wstring::npos) return false;
  const bool json_wrapped = argument.front() == L'{';
  if (!json_wrapped) {
    *payload = argument.substr(best);
    return true;
  }
  std::wstring out;
  for (size_t index = best; index < argument.size(); ++index) {
    const wchar_t c = argument[index];
    if (c == L'"') break;
    if (c != L'\\') {
      out.push_back(c);
      continue;
    }
    if (++index >= argument.size()) break;
    const wchar_t escape = argument[index];
    switch (escape) {
      case L'"': out.push_back(L'"'); break;
      case L'\\': out.push_back(L'\\'); break;
      case L'/': out.push_back(L'/'); break;
      case L'b': out.push_back(L'\b'); break;
      case L'f': out.push_back(L'\f'); break;
      case L'n': out.push_back(L'\n'); break;
      case L'r': out.push_back(L'\r'); break;
      case L't': out.push_back(L'\t'); break;
      case L'u': {
        if (index + 4 >= argument.size()) return false;
        unsigned code = 0;
        for (int digit = 0; digit < 4; ++digit) {
          const wchar_t hex = argument[++index];
          code <<= 4;
          if (hex >= L'0' && hex <= L'9') {
            code |= static_cast<unsigned>(hex - L'0');
          } else if (hex >= L'a' && hex <= L'f') {
            code |= static_cast<unsigned>(hex - L'a' + 10);
          } else if (hex >= L'A' && hex <= L'F') {
            code |= static_cast<unsigned>(hex - L'A' + 10);
          } else {
            return false;
          }
        }
        out.push_back(static_cast<wchar_t>(code));
        break;
      }
      default: out.push_back(escape); break;
    }
  }
  if (out.empty()) return false;
  *payload = std::move(out);
  return true;
}

// Reads the per-user toast switch. This is a read-only query: the product never
// edits notification settings for the person.
bool ReadToastEnabled() {
  DWORD value = 1;
  DWORD size = sizeof(value);
  const LSTATUS status = ::RegGetValueW(
      HKEY_CURRENT_USER,
      L"Software\\Microsoft\\Windows\\CurrentVersion\\PushNotifications",
      L"ToastEnabled", RRF_RT_REG_DWORD, nullptr, &value, &size);
  if (status == ERROR_FILE_NOT_FOUND || status == ERROR_PATH_NOT_FOUND) return true;
  if (status != ERROR_SUCCESS) return true;
  return value != 0;
}

WDN::XmlDocument BuildToastDocument(const std::wstring& title,
                                    const std::wstring& body,
                                    const std::wstring& payload) {
  WDN::XmlDocument document;
  auto toast = document.CreateElement(L"toast");
  // DOM APIs escape attribute values, so quotes, ampersands and non-ASCII text
  // survive without hand-written entity replacement.
  toast.SetAttribute(L"launch", hstring(payload.c_str()));
  auto visual = document.CreateElement(L"visual");
  auto binding = document.CreateElement(L"binding");
  binding.SetAttribute(L"template", hstring(L"ToastGeneric"));
  auto title_node = document.CreateElement(L"text");
  title_node.InnerText(hstring(title.c_str()));
  auto body_node = document.CreateElement(L"text");
  body_node.InnerText(hstring(body.c_str()));
  binding.AppendChild(title_node);
  binding.AppendChild(body_node);
  visual.AppendChild(binding);
  toast.AppendChild(visual);
  document.AppendChild(toast);
  return document;
}

// AppNotificationManager is a WinRT runtime class, which deliberately deletes
// operator new. The manager therefore lives as a member of an ordinary object.
struct ManagerHolder {
  explicit ManagerHolder(ANA::AppNotificationManager value)
      : manager(std::move(value)) {}
  ANA::AppNotificationManager manager;
};

ANA::AppNotificationManager* ManagerOf(void* storage) {
  return storage == nullptr
             ? nullptr
             : &static_cast<ManagerHolder*>(storage)->manager;
}

}  // namespace

WindowsNotificationBridge::WindowsNotificationBridge() = default;
WindowsNotificationBridge::~WindowsNotificationBridge() { Stop(); }

bool WindowsNotificationBridge::Start(std::string* error_code,
                                      std::string* error_message,
                                      int32_t* error_hresult) {
  if (registered_) return true;
  if (error_code) error_code->clear();
  if (error_message) error_message->clear();
  if (error_hresult) *error_hresult = 0;

  aumid_ = ResolveAppUserModelId(&identity_source_);
  if (aumid_.empty() || aumid_.size() > kMaxAumidLength) {
    RecordError("aumid_rejected", "The notification identity is empty or too long.",
                E_INVALIDARG, error_code, error_message, error_hresult);
    return false;
  }
  if (identity_source_ == "fixture-file-rejected") {
    RecordError("aumid_rejected",
                "The fixture identity must be a Pacta.Test.* AppUserModelId.",
                E_INVALIDARG, error_code, error_message, error_hresult);
    return false;
  }

  // The identity is captured by the SDK when Default() first runs and cannot be
  // changed for the rest of the process.
  const HRESULT set_id_status =
      ::SetCurrentProcessExplicitAppUserModelID(aumid_.c_str());
  if (FAILED(set_id_status)) {
    RecordError("aumid_rejected",
                "Windows rejected the explicit AppUserModelId for this process.",
                static_cast<int32_t>(set_id_status), error_code, error_message,
                error_hresult);
    return false;
  }

  try {
    if (!ANA::AppNotificationManager::IsSupported()) {
      RecordError("sdk_unsupported",
                  "Windows App SDK notifications are not supported on this system.",
                  static_cast<int32_t>(E_NOTIMPL), error_code, error_message,
                  error_hresult);
      return false;
    }
    auto manager = ANA::AppNotificationManager::Default();
    manager_ = new ManagerHolder(std::move(manager));
    auto* stored = ManagerOf(manager_);
    handler_token_ = stored
                         ->NotificationInvoked(
                             [this](const auto&,
                                    const ANA::AppNotificationActivatedEventArgs&
                                        args) noexcept {
                               try {
                                 OnNotificationInvoked(std::wstring(args.Argument().c_str()));
                               } catch (...) {
                                 // A callback must never escape into the SDK thread.
                               }
                             })
                         .value;
    handler_attached_ = true;
    stored->Register();
    registered_ = true;
    return true;
  } catch (const winrt::hresult_error& error) {
    RecordError("register_failed",
                ToUtf8(std::wstring(error.message().c_str())),
                static_cast<int32_t>(error.code().value), error_code,
                error_message, error_hresult);
  } catch (...) {
    RecordError("register_failed", "Registering AppNotificationManager failed.",
                static_cast<int32_t>(E_FAIL), error_code, error_message,
                error_hresult);
  }

  // A half-registered manager cannot be reused: revoke the handler and drop the
  // manager. The schedule is untouched because nothing was scheduled yet.
  if (manager_ != nullptr) {
    auto* manager = ManagerOf(manager_);
    try {
      if (handler_attached_) manager->NotificationInvoked(winrt::event_token{handler_token_});
    } catch (...) {
    }
    delete static_cast<ManagerHolder*>(manager_);
    manager_ = nullptr;
  }
  handler_attached_ = false;
  handler_token_ = 0;
  registered_ = false;
  return false;
}

void WindowsNotificationBridge::Stop() {
  stopping_ = true;
  dart_ready_ = false;
  if (manager_ == nullptr) {
    registered_ = false;
    return;
  }
  auto* manager = ManagerOf(manager_);
  // Intake first, then the public Unregister, which releases the live COM
  // registration but keeps already scheduled reminders in the OS queue.
  if (handler_attached_) {
    try {
      manager->NotificationInvoked(winrt::event_token{handler_token_});
    } catch (...) {
    }
    handler_attached_ = false;
    handler_token_ = 0;
  }
  try {
    if (registered_) manager->Unregister();
  } catch (...) {
  }
  if (manager_ != nullptr) delete static_cast<ManagerHolder*>(manager_);
  manager_ = nullptr;
  registered_ = false;
}

void WindowsNotificationBridge::AttachWindow(
    HWND window, std::function<void(const std::string&)> emit_click) {
  window_ = window;
  emit_click_ = std::move(emit_click);
}

void WindowsNotificationBridge::DetachWindow() {
  window_ = nullptr;
  emit_click_ = nullptr;
  dart_ready_ = false;
}

void WindowsNotificationBridge::SetDartReady(bool ready) {
  dart_ready_ = ready;
  if (ready && window_ != nullptr) {
    ::PostMessageW(window_, kNotificationActivationMessage, 0, 0);
  }
}

void WindowsNotificationBridge::DrainPendingActivations() {
  if (!dart_ready_) return;
  std::deque<std::string> drained;
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    drained.swap(pending_activations_);
  }
  for (const std::string& payload : drained) {
    if (emit_click_) emit_click_(payload);
  }
}

void WindowsNotificationBridge::OnNotificationInvoked(
    const std::wstring& argument) noexcept {
  if (stopping_) return;
  std::wstring payload;
  if (!ExtractPayload(argument, &payload) || payload.empty()) {
    // A cold-start marker without our payload is not a reminder activation.
    return;
  }
  if (payload.size() > 4096) return;
  EnqueueActivation(ToUtf8(payload));
}

void WindowsNotificationBridge::EnqueueActivation(const std::string& payload) {
  if (payload.empty()) return;
  {
    std::lock_guard<std::mutex> lock(queue_mutex_);
    if (pending_activations_.size() >= 32) pending_activations_.pop_front();
    pending_activations_.push_back(payload);
  }
  if (window_ != nullptr) {
    ::PostMessageW(window_, kNotificationActivationMessage, 0, 0);
  }
}

bool WindowsNotificationBridge::Schedule(int64_t id, const std::wstring& title,
                                         const std::wstring& body,
                                         int64_t due_unix_ms,
                                         const std::wstring& payload,
                                         std::string* error_code,
                                         std::string* error_message,
                                         int32_t* error_hresult) {
  if (error_code) error_code->clear();
  if (error_message) error_message->clear();
  if (error_hresult) *error_hresult = 0;
  if (!registered_ || manager_ == nullptr) {
    RecordError("not_registered",
                "Windows notifications are not registered in this process.",
                static_cast<int32_t>(E_UNEXPECTED), error_code, error_message,
                error_hresult);
    return false;
  }
  if (id < 0) {
    RecordError("id_out_of_range", "Notification ids must be non-negative.",
                static_cast<int32_t>(E_INVALIDARG), error_code, error_message,
                error_hresult);
    return false;
  }
  const std::wstring id_text = std::to_wstring(id);
  if (id_text.size() > kMaxScheduledIdDigits) {
    RecordError("id_out_of_range",
                "Notification ids must fit the 16-character toast id limit.",
                static_cast<int32_t>(E_INVALIDARG), error_code, error_message,
                error_hresult);
    return false;
  }
  int64_t due_ticks = 0;
  if (!UnixMsToFileTime(due_unix_ms, &due_ticks)) {
    RecordError("due_invalid",
                "The reminder time is in the past or outside the supported range.",
                static_cast<int32_t>(E_INVALIDARG), error_code, error_message,
                error_hresult);
    return false;
  }
  if (due_ticks <= NowFileTimeTicks()) {
    RecordError("due_in_past", "The reminder time has already passed.",
                static_cast<int32_t>(E_INVALIDARG), error_code, error_message,
                error_hresult);
    return false;
  }

  try {
    const WDN::XmlDocument document = BuildToastDocument(title, body, payload);
    WUN::ScheduledToastNotification scheduled(
        document, WF::DateTime{WF::DateTime::duration{due_ticks}});
    scheduled.Tag(hstring(kScheduledTag));
    scheduled.Group(hstring(kScheduledGroup));
    scheduled.Id(hstring(id_text));

    auto notifier = WUN::ToastNotificationManager::CreateToastNotifier(
        hstring(aumid_.c_str()));
    // Replace, never stack: an edited reminder must leave exactly one pending
    // item for its id.
    std::vector<WUN::ScheduledToastNotification> replaced;
    for (const auto& existing : notifier.GetScheduledToastNotifications()) {
      if (existing.Id() == hstring(id_text)) replaced.push_back(existing);
    }
    for (const auto& existing : replaced) notifier.RemoveFromSchedule(existing);
    notifier.AddToSchedule(scheduled);
    return true;
  } catch (const winrt::hresult_error& error) {
    RecordError("schedule_failed",
                ToUtf8(std::wstring(error.message().c_str())),
                static_cast<int32_t>(error.code().value), error_code,
                error_message, error_hresult);
  } catch (...) {
    RecordError("schedule_failed", "Scheduling the reminder failed.",
                static_cast<int32_t>(E_FAIL), error_code, error_message,
                error_hresult);
  }
  return false;
}

bool WindowsNotificationBridge::Cancel(int64_t id, std::string* error_code,
                                       std::string* error_message,
                                       int32_t* error_hresult) {
  if (error_code) error_code->clear();
  if (error_message) error_message->clear();
  if (error_hresult) *error_hresult = 0;
  if (!registered_ || manager_ == nullptr) {
    RecordError("not_registered",
                "Windows notifications are not registered in this process.",
                static_cast<int32_t>(E_UNEXPECTED), error_code, error_message,
                error_hresult);
    return false;
  }
  try {
    const hstring id_text(std::to_wstring(id));
    auto notifier = WUN::ToastNotificationManager::CreateToastNotifier(
        hstring(aumid_.c_str()));
    std::vector<WUN::ScheduledToastNotification> removed;
    for (const auto& existing : notifier.GetScheduledToastNotifications()) {
      if (existing.Id() == id_text) removed.push_back(existing);
    }
    for (const auto& existing : removed) notifier.RemoveFromSchedule(existing);
    return true;
  } catch (const winrt::hresult_error& error) {
    RecordError("cancel_failed",
                ToUtf8(std::wstring(error.message().c_str())),
                static_cast<int32_t>(error.code().value), error_code,
                error_message, error_hresult);
  } catch (...) {
    RecordError("cancel_failed", "Cancelling the reminder failed.",
                static_cast<int32_t>(E_FAIL), error_code, error_message,
                error_hresult);
  }
  return false;
}

bool WindowsNotificationBridge::PendingIds(std::vector<int64_t>* ids,
                                           std::string* error_code,
                                           std::string* error_message,
                                           int32_t* error_hresult) {
  if (error_code) error_code->clear();
  if (error_message) error_message->clear();
  if (error_hresult) *error_hresult = 0;
  if (ids == nullptr) return false;
  ids->clear();
  if (!registered_ || manager_ == nullptr) {
    RecordError("not_registered",
                "Windows notifications are not registered in this process.",
                static_cast<int32_t>(E_UNEXPECTED), error_code, error_message,
                error_hresult);
    return false;
  }
  try {
    auto notifier = WUN::ToastNotificationManager::CreateToastNotifier(
        hstring(aumid_.c_str()));
    for (const auto& existing : notifier.GetScheduledToastNotifications()) {
      const std::wstring value(existing.Id().c_str());
      if (value.empty() || value.size() > kMaxScheduledIdDigits) continue;
      wchar_t* end = nullptr;
      const long long parsed = std::wcstoll(value.c_str(), &end, 10);
      if (end == nullptr || *end != L'\0' || parsed < 0) continue;
      ids->push_back(static_cast<int64_t>(parsed));
    }
    return true;
  } catch (const winrt::hresult_error& error) {
    RecordError("pending_failed",
                ToUtf8(std::wstring(error.message().c_str())),
                static_cast<int32_t>(error.code().value), error_code,
                error_message, error_hresult);
  } catch (...) {
    RecordError("pending_failed", "Reading the OS reminder queue failed.",
                static_cast<int32_t>(E_FAIL), error_code, error_message,
                error_hresult);
  }
  return false;
}

bool WindowsNotificationBridge::NotificationsEnabled(bool* enabled) {
  if (enabled == nullptr) return false;
  *enabled = ReadToastEnabled();
  return true;
}

bool WindowsNotificationBridge::UnregisterAllForTestIdentity(
    std::string* error_code, std::string* error_message, int32_t* error_hresult) {
  if (error_code) error_code->clear();
  if (error_message) error_message->clear();
  if (error_hresult) *error_hresult = 0;
  // Two independent guards: a Pacta.Test.* identity and an explicit runtime
  // opt-in. The product identity and a normal launch can never reach it.
  if (!IsTestIdentity(aumid_)) {
    RecordError("test_only",
                "Permanent deregistration is limited to a Pacta.Test.* identity.",
                static_cast<int32_t>(E_ACCESSDENIED), error_code, error_message,
                error_hresult);
    return false;
  }
  if (!FixtureTeardownAllowed()) {
    RecordError(
        "test_only",
        "Set PACTA_NOTIFICATION_FIXTURE_ALLOW_UNREGISTER_ALL=1 to allow it.",
        static_cast<int32_t>(E_ACCESSDENIED), error_code, error_message,
        error_hresult);
    return false;
  }
  if (!registered_ || manager_ == nullptr) {
    RecordError("not_registered",
                "Windows notifications are not registered in this process.",
                static_cast<int32_t>(E_UNEXPECTED), error_code, error_message,
                error_hresult);
    return false;
  }
  auto* manager = ManagerOf(manager_);
  try {
    manager->UnregisterAll();
  } catch (const winrt::hresult_error& error) {
    RecordError("unregister_all_failed",
                ToUtf8(std::wstring(error.message().c_str())),
                static_cast<int32_t>(error.code().value), error_code,
                error_message, error_hresult);
    return false;
  } catch (...) {
    RecordError("unregister_all_failed",
                "Permanent deregistration failed.", static_cast<int32_t>(E_FAIL),
                error_code, error_message, error_hresult);
    return false;
  }
  registered_ = false;
  return true;
}

void WindowsNotificationBridge::RecordError(const std::string& code,
                                            const std::string& message,
                                            int32_t hresult,
                                            std::string* error_code,
                                            std::string* error_message,
                                            int32_t* error_hresult) {
  if (error_code) *error_code = code;
  if (error_message) *error_message = message;
  if (error_hresult) *error_hresult = hresult;
}

}  // namespace pacta
