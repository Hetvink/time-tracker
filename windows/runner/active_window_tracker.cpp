#include "active_window_tracker.h"
#include <chrono>
#include <iostream>
#include <psapi.h>
#include <thread>
#include <tlhelp32.h>

#pragma comment(lib, "psapi.lib")

ActiveWindowTracker *ActiveWindowTracker::instance_ = nullptr;

ActiveWindowTracker::ActiveWindowTracker(ActivityCallback callback)
    : callback_(callback) {
  instance_ = this;
}

ActiveWindowTracker::~ActiveWindowTracker() {
  StopTracking();
  instance_ = nullptr;
}

void ActiveWindowTracker::StartTracking() {
  if (is_tracking_) {
    std::cout << "[TRACKER] Already tracking" << std::endl;
    return;
  }

  is_tracking_ = true;

  // Set up Windows event hook for foreground window changes (app-switch
  // detection) EVENT_SYSTEM_FOREGROUND fires when a DIFFERENT process gets
  // focus
  event_hook_ =
      SetWinEventHook(EVENT_SYSTEM_FOREGROUND, // eventMin - window gained focus
                      EVENT_SYSTEM_FOREGROUND, // eventMax - same event
                      nullptr,                 // hmodWinEventProc
                      WinEventProc, // lpfnWinEventProc - our callback
                      0,            // idProcess - all processes
                      0,            // idThread - all threads
                      WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS);

  if (event_hook_ == nullptr) {
    std::cerr << "[TRACKER] Failed to set up window event hook" << std::endl;
    is_tracking_ = false;
    return;
  }

  // Check immediately to get current active window
  CheckActiveWindow();

  // Start background polling thread to detect in-app title changes every 2s
  // (EVENT_SYSTEM_FOREGROUND only fires on app switch, not in-app navigation)
  should_poll_ = true;
  poll_thread_ = std::thread(&ActiveWindowTracker::PollLoop, this);

  std::cout << "[TRACKER] Real-time activity tracking started (with 2s in-app "
               "title polling)"
            << std::endl;
}

void ActiveWindowTracker::StopTracking() {
  if (!is_tracking_) {
    return;
  }

  if (event_hook_ != nullptr) {
    UnhookWinEvent(event_hook_);
    event_hook_ = nullptr;
  }

  // Stop polling thread
  should_poll_ = false;
  if (poll_thread_.joinable()) {
    poll_thread_.join();
  }

  is_tracking_ = false;
  std::cout << "[TRACKER] Activity tracking stopped" << std::endl;
}

// Background polling loop: checks for in-app title changes every 2 seconds
// This is needed because EVENT_SYSTEM_FOREGROUND only fires on process switch
void ActiveWindowTracker::PollLoop() {
  while (should_poll_) {
    // Sleep 2 seconds between polls
    for (int i = 0; i < 20 && should_poll_; ++i) {
      std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    if (should_poll_) {
      CheckActiveWindow();
    }
  }
}

void CALLBACK ActiveWindowTracker::WinEventProc(HWINEVENTHOOK hWinEventHook,
                                                DWORD event, HWND hwnd,
                                                LONG idObject, LONG idChild,
                                                DWORD dwEventThread,
                                                DWORD dwmsEventTime) {
  // Called immediately when any window gains foreground focus
  if (event == EVENT_SYSTEM_FOREGROUND && instance_) {
    instance_->CheckActiveWindow();
  }
}

void ActiveWindowTracker::CheckActiveWindow() {
  HWND foreground_window = GetForegroundWindow();
  if (!foreground_window) {
    return;
  }

  // Get process ID
  DWORD process_id = 0;
  GetWindowThreadProcessId(foreground_window, &process_id);

  // Get window title
  std::wstring window_title_w = GetWindowText(foreground_window);
  std::string window_title(window_title_w.begin(), window_title_w.end());

  // Get process name and path
  std::string process_name = GetProcessName(process_id);
  std::string process_path = GetProcessPath(process_id);

  // Log if window title is empty (helps diagnose issues)
  if (window_title.empty() && process_name != last_app_name_) {
    std::cout << "[TRACKER] No window title for: " << process_name
              << " (window may not have a title)" << std::endl;
  }

  // Check if changed
  // IMPORTANT: Always treat window title changes as NEW activities (even within
  // same app) This ensures switching files (e.g., file1.dart -> file2.dart)
  // creates separate work sessions
  bool app_changed = (process_name != last_app_name_);
  bool title_changed = (window_title != last_window_title_);
  bool path_changed = (process_path != last_process_path_);
  bool changed = app_changed || title_changed || path_changed;

  // Always notify if ANYTHING changed (app, window title, or path)
  if (changed) {
    std::string title_display =
        window_title.empty() ? "(no title)" : window_title;
    std::cout << "[TRACKER] ✓ Activity: " << process_name << " - "
              << title_display << std::endl;

    // Log when switching files within same app
    if (!app_changed && title_changed) {
      std::cout << "[TRACKER] → File/Window switched within same app - "
                   "creating new work session"
                << std::endl;
    }

    last_app_name_ = process_name;
    last_window_title_ = window_title;
    last_process_path_ = process_path;

    // Always notify to create new work session
    if (callback_) {
      callback_(process_name, window_title, process_path);
    }
  }
}

std::string ActiveWindowTracker::GetProcessName(DWORD process_id) {
  HANDLE process_handle = OpenProcess(
      PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, process_id);
  if (!process_handle) {
    return "Unknown";
  }

  wchar_t process_name[MAX_PATH] = L"<unknown>";
  HMODULE module;
  DWORD needed;

  if (EnumProcessModules(process_handle, &module, sizeof(module), &needed)) {
    GetModuleBaseNameW(process_handle, module, process_name, MAX_PATH);
  }

  CloseHandle(process_handle);

  std::wstring name_w(process_name);
  std::string name(name_w.begin(), name_w.end());

  // Remove .exe extension
  size_t dot_pos = name.find_last_of('.');
  if (dot_pos != std::string::npos) {
    name = name.substr(0, dot_pos);
  }

  return name;
}

std::string ActiveWindowTracker::GetProcessPath(DWORD process_id) {
  HANDLE process_handle = OpenProcess(
      PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, process_id);
  if (!process_handle) {
    return "";
  }

  wchar_t path[MAX_PATH];
  DWORD path_len =
      GetModuleFileNameExW(process_handle, nullptr, path, MAX_PATH);

  CloseHandle(process_handle);

  if (path_len > 0) {
    std::wstring path_w(path);
    return std::string(path_w.begin(), path_w.end());
  }

  return "";
}

std::wstring ActiveWindowTracker::GetWindowText(HWND hwnd) {
  int length = ::GetWindowTextLengthW(hwnd);
  if (length == 0) {
    return L"";
  }

  std::wstring text(length + 1, L'\0');
  ::GetWindowTextW(hwnd, &text[0], length + 1);
  text.resize(length);

  return text;
}

ActiveWindowTracker::CurrentActivity ActiveWindowTracker::GetCurrentActivity() {
  HWND foreground_window = GetForegroundWindow();
  CurrentActivity activity;

  if (!foreground_window) {
    return activity;
  }

  DWORD process_id = 0;
  GetWindowThreadProcessId(foreground_window, &process_id);

  std::wstring window_title_w = GetWindowText(foreground_window);
  activity.window_title =
      std::string(window_title_w.begin(), window_title_w.end());
  activity.app_name = GetProcessName(process_id);
  activity.process_path = GetProcessPath(process_id);

  return activity;
}
