#include "single_instance.h"

#include "win32_window.h"

namespace {

// Per-session, so two users on one machine each get their own instance.
constexpr wchar_t kMutexName[] = L"Local\\MeowChess.Instance";

// Held by every running copy, including one that keeps to itself, so the
// uninstaller (packaging/windows/installer.iss) can tell the app is open.
constexpr wchar_t kRunningMutexName[] = L"Local\\MeowChess.Running";

// Held for the life of the process; the OS releases them on exit.
HANDLE g_instance_mutex = nullptr;
HANDLE g_running_mutex = nullptr;

// How long a forwarded WM_COPYDATA may take before the running instance is
// treated as unreachable.
constexpr UINT kForwardTimeoutMs = 5000;

// Debug builds stay independent so `flutter run` and integration tests never
// hand off to an open copy; MEOW_CHESS_NEW_INSTANCE=1 does the same for a
// release build. Mirrors linux/runner/my_application.cc.
bool WantsOwnInstance() {
#ifdef _DEBUG
  return true;
#else
  wchar_t value[2] = {};
  DWORD length =
      ::GetEnvironmentVariableW(L"MEOW_CHESS_NEW_INSTANCE", value, 2);
  return length == 1 && value[0] == L'1';
#endif
}

// The running instance may still be starting up (two files double-clicked
// together), so give its window a moment to appear.
HWND FindRunningInstance() {
  for (int attempt = 0; attempt < 50; ++attempt) {
    HWND window = ::FindWindowW(kWindowClassName, nullptr);
    if (window != nullptr) return window;
    ::Sleep(100);
  }
  return nullptr;
}

}  // namespace

bool ClaimSingleInstance(const std::vector<std::string>& paths) {
  g_running_mutex = ::CreateMutexW(nullptr, FALSE, kRunningMutexName);
  if (WantsOwnInstance()) return true;

  g_instance_mutex = ::CreateMutexW(nullptr, FALSE, kMutexName);
  if (g_instance_mutex == nullptr ||
      ::GetLastError() != ERROR_ALREADY_EXISTS) {
    return true;
  }

  HWND target = FindRunningInstance();
  if (target == nullptr) {
    // Cannot reach it: better a second window than a click that does
    // nothing.
    return true;
  }

  if (!paths.empty()) {
    std::string payload;
    for (const std::string& path : paths) {
      if (!payload.empty()) payload += '\n';
      payload += path;
    }
    COPYDATASTRUCT data{};
    data.dwData = kOpenFilesCopyData;
    data.cbData = static_cast<DWORD>(payload.size());
    data.lpData = const_cast<char*>(payload.data());
    DWORD_PTR handled = 0;
    LRESULT sent = ::SendMessageTimeoutW(
        target, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data),
        SMTO_ABORTIFHUNG | SMTO_BLOCK, kForwardTimeoutMs, &handled);
    if (sent == 0 || handled == 0) {
      // Hung, blocked, or not taking files yet: open them here instead of
      // dropping them.
      return true;
    }
  }

  if (::IsIconic(target)) ::ShowWindow(target, SW_RESTORE);
  ::SetForegroundWindow(target);
  return false;
}

std::vector<std::string> DecodeOpenFiles(const COPYDATASTRUCT& data) {
  std::vector<std::string> paths;
  if (data.dwData != kOpenFilesCopyData || data.lpData == nullptr) {
    return paths;
  }
  std::string payload(static_cast<const char*>(data.lpData), data.cbData);
  size_t start = 0;
  while (start <= payload.size()) {
    size_t end = payload.find('\n', start);
    if (end == std::string::npos) end = payload.size();
    if (end > start) paths.push_back(payload.substr(start, end - start));
    start = end + 1;
  }
  return paths;
}
