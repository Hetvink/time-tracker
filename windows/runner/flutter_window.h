#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>

#include "active_window_tracker.h"
#include "power_monitor.h"
#include "startup_manager.h"
#include "system_tray.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject &project);
  virtual ~FlutterWindow();

protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

private:
  void SetupPlatformChannel();
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void SendSystemEvent(const std::string &event_type);
  void SendBreakConfirmation(bool was_on_break, const std::string &sleep_start,
                             const std::string &wake_time, const std::string &note);
  void SendActivityChange(const std::string &app_name,
                          const std::string &window_title,
                          const std::string &process_path);
  void HandleTrayMenuClick(int menu_id);
  void UpdateTrayFromFlutter(const flutter::EncodableMap &args);
  void UpdateMenuItemsFromFlutter(const flutter::EncodableMap &args);
  void NotifySystemBoot(); // Show auto check-in dialog after login

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Platform channel for communication with Flutter
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      platform_channel_;

  // Windows-specific components
  std::unique_ptr<SystemTray> system_tray_;
  std::unique_ptr<PowerMonitor> power_monitor_;
  std::unique_ptr<ActiveWindowTracker> window_tracker_;
  bool is_tracking_enabled_ = false;
  bool is_user_authenticated_ = false;

  // Break confirmation callback for main thread processing
  PowerMonitor::BreakConfirmationCallback break_callback_;

  // Midnight monitoring
  static constexpr UINT_PTR MIDNIGHT_TIMER_ID = 1001;
  // Boot retry timer (resend boot event a few times to avoid missed messages)
  static constexpr UINT_PTR BOOT_RETRY_TIMER_ID = 1002;
  // Quit timer (allow Flutter to save state before destroying window)
  static constexpr UINT_PTR QUIT_TIMER_ID = 1003;
  int boot_retry_count_ = 0;
  void StartMidnightMonitor();
  void CheckForMidnight();
};

#endif // RUNNER_FLUTTER_WINDOW_H_
