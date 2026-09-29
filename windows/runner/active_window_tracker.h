#ifndef ACTIVE_WINDOW_TRACKER_H_
#define ACTIVE_WINDOW_TRACKER_H_

#include <windows.h>
#include <string>
#include <functional>
#include <thread>
#include <atomic>

class ActiveWindowTracker {
 public:
  using ActivityCallback = std::function<void(
      const std::string& app_name,
      const std::string& window_title,
      const std::string& process_path)>;

  explicit ActiveWindowTracker(ActivityCallback callback);
  ~ActiveWindowTracker();

  void StartTracking();
  void StopTracking();
  bool IsTracking() const { return is_tracking_; }

  struct CurrentActivity {
    std::string app_name;
    std::string window_title;
    std::string process_path;
  };

  CurrentActivity GetCurrentActivity();

 private:
  static void CALLBACK WinEventProc(
      HWINEVENTHOOK hWinEventHook,
      DWORD event,
      HWND hwnd,
      LONG idObject,
      LONG idChild,
      DWORD dwEventThread,
      DWORD dwmsEventTime);

  void CheckActiveWindow();
  void PollLoop(); // Background polling thread for in-app title changes
  std::string GetProcessName(DWORD process_id);
  std::string GetProcessPath(DWORD process_id);
  std::wstring GetWindowText(HWND hwnd);

  ActivityCallback callback_;
  bool is_tracking_ = false;
  HWINEVENTHOOK event_hook_ = nullptr;
  std::string last_app_name_;
  std::string last_window_title_;
  std::string last_process_path_;

  // Background thread polls every 2 seconds to detect in-app title changes
  // (EVENT_SYSTEM_FOREGROUND only fires on app switch, not in-app navigation)
  std::thread poll_thread_;
  std::atomic<bool> should_poll_{false};

  static ActiveWindowTracker* instance_;
};

#endif  // ACTIVE_WINDOW_TRACKER_H_
