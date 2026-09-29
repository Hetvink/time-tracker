#ifndef RUNNER_POWER_MONITOR_H_
#define RUNNER_POWER_MONITOR_H_

#include <functional>
#include <string>
#include <windows.h>

class PowerMonitor {
public:
  using PowerEventCallback = std::function<void(const std::string &)>;
  using BreakConfirmationCallback =
      std::function<void(bool, const std::string &, const std::string &, const std::string &)>;

  PowerMonitor(HWND hwnd);
  ~PowerMonitor();

  // Register for power notifications
  bool RegisterNotifications();

  // Handle power broadcast messages
  void HandlePowerEvent(WPARAM event);

  // Handle shutdown messages
  bool HandleShutdown(WPARAM event);

  // Set callback for power events
  void SetCallback(PowerEventCallback callback);

  // Set callback for break confirmation
  void SetBreakConfirmationCallback(BreakConfirmationCallback callback);

  // Set sleep threshold in seconds
  void SetSleepThreshold(int seconds);

private:
  HWND window_;
  HPOWERNOTIFY power_notify_;
  PowerEventCallback callback_;
  BreakConfirmationCallback break_callback_;

  // Sleep tracking
  SYSTEMTIME sleep_start_time_;
  int sleep_threshold_seconds_ = 1800; // Default 30 minutes (increased from 15 to prevent false triggers)
  bool is_sleeping_ = false;
  bool is_showing_dialog_ = false;

  // Helper methods
  void ShowBreakConfirmationDialog(SYSTEMTIME sleep_start, SYSTEMTIME wake_time,
                                   int duration_seconds);
  void ShowWorkNoteDialog(SYSTEMTIME sleep_start, SYSTEMTIME wake_time);
  void SendBreakConfirmation(bool was_on_break, SYSTEMTIME sleep_start,
                             SYSTEMTIME wake_time, const std::string &note = "");
  std::string SystemTimeToISO8601(const SYSTEMTIME &st);
  int CalculateDurationSeconds(const SYSTEMTIME &start, const SYSTEMTIME &end);

  // Dialog procedure for work note input
  static LRESULT CALLBACK WorkNoteDialogProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam);

  // Struct to pass data to dialog
  struct WorkNoteDialogData {
    std::wstring note;
    bool cancelled;
  };
};

#endif // RUNNER_POWER_MONITOR_H_
