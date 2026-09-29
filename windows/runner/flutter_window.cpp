#include "flutter_window.h"

#include <optional>
#include <shellapi.h>
#include <thread>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject &project)
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

  // Setup platform channel for communication with Flutter
  SetupPlatformChannel();

  // Initialize system tray
  system_tray_ =
      std::make_unique<SystemTray>(GetHandle(), GetModuleHandle(NULL));
  if (system_tray_->Initialize()) {
    system_tray_->SetMenuCallback(
        [this](int menu_id) { HandleTrayMenuClick(menu_id); });
  }

  // Initialize power monitor
  power_monitor_ = std::make_unique<PowerMonitor>(GetHandle());
  power_monitor_->RegisterNotifications();
  power_monitor_->SetCallback(
      [this](const std::string &event) { SendSystemEvent(event); });

  // Store break callback for main thread processing
  break_callback_ = [this](bool was_on_break, const std::string &sleep_start,
                           const std::string &wake_time,
                           const std::string &note) {
    SendBreakConfirmation(was_on_break, sleep_start, wake_time, note);
  };

  power_monitor_->SetBreakConfirmationCallback(break_callback_);

  // Initialize activity tracker
  window_tracker_ = std::make_unique<ActiveWindowTracker>(
      [this](const std::string &app_name, const std::string &window_title,
             const std::string &process_path) {
        SendActivityChange(app_name, window_title, process_path);
      });

  // Enable auto-start
  StartupManager::EnableAutoStart();

  // Note: defer sending the boot event until after the first Flutter frame
  // to ensure Dart's MethodChannel handler is registered and ready to
  // receive platform events. The boot event will be sent in the
  // SetNextFrameCallback below.

  // Start midnight monitor
  StartMidnightMonitor();

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    this->Show();

    // Don't automatically show boot dialog on app launch
    // Instead, it will be triggered manually after user logs in (via
    // triggerBootEvent) This ensures the auto check-in dialog only shows when
    // user is authenticated
    OutputDebugString(
        L"[BOOT] App started - boot dialog will show after login\n");
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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

  case WM_CLOSE:
    // Minimize to tray instead of closing - only close on explicit Quit
    OutputDebugString(L"[NATIVE] WM_CLOSE received - hiding window to tray\n");
    ShowWindow(hwnd, SW_HIDE);
    OutputDebugString(L"[NATIVE] Window hidden to tray\n");
    return 0;

  case WM_TRAYICON:
    if (system_tray_) {
      system_tray_->HandleTrayMessage(wparam, lparam);
    }
    return 0;

  case WM_POWERBROADCAST:
    if (power_monitor_) {
      power_monitor_->HandlePowerEvent(wparam);
    }
    return TRUE;

  case WM_QUERYENDSESSION:
    if (power_monitor_) {
      power_monitor_->HandleShutdown(wparam);
    }
    return TRUE;

  case WM_TIMER:
    if (wparam == MIDNIGHT_TIMER_ID) {
      CheckForMidnight();
      return 0;
    }

    if (wparam == QUIT_TIMER_ID) {
      // Timer expired, now safe to destroy window after Flutter saved state
      OutputDebugString(L"[NATIVE] Quit timer expired, destroying window\n");
      KillTimer(GetHandle(), QUIT_TIMER_ID);
      DestroyWindow(GetHandle());
      return 0;
    }

    if (wparam == BOOT_RETRY_TIMER_ID) {
      if (boot_retry_count_ > 0) {
        // Resend boot event - harmless if Flutter already handled it
        wchar_t debug_msg[100];
        swprintf_s(debug_msg, L"[NATIVE] Retry boot event #%d\n",
                   11 - boot_retry_count_);
        OutputDebugString(debug_msg);
        SendSystemEvent("boot");
        --boot_retry_count_;
      }
      if (boot_retry_count_ <= 0) {
        OutputDebugString(L"[NATIVE] Boot retry timer complete\n");
        KillTimer(GetHandle(), BOOT_RETRY_TIMER_ID);
      }
      return 0;
    }
    break;

  // Handle break confirmation posted from background thread by SendBreakConfirmation()
  // This MUST be its own case - PostMessage sends message=WM_USER+100, not WM_TIMER.
  case WM_USER + 100:
    try {
      // All data is packed into a single heap-allocated string in lparam.
      // Format: was_on_break|sleep_start|wake_time|note
      std::string *data_str = reinterpret_cast<std::string *>(lparam);

      if (data_str) {
        std::string data = *data_str;
        size_t pos1 = data.find("|");
        size_t pos2 = data.find("|", pos1 + 1);
        size_t pos3 = data.find("|", pos2 + 1);

        if (pos1 != std::string::npos && pos2 != std::string::npos &&
            pos3 != std::string::npos) {
          std::string was_on_break = data.substr(0, pos1);
          std::string sleep_start = data.substr(pos1 + 1, pos2 - pos1 - 1);
          std::string wake_time = data.substr(pos2 + 1, pos3 - pos2 - 1);
          std::string note = data.substr(pos3 + 1);

          OutputDebugStringA("[NATIVE] Break confirmation received on main thread\n");

          // Forward to Flutter via platform channel (main thread - safe)
          if (power_monitor_ && break_callback_) {
            break_callback_(was_on_break == "true", sleep_start, wake_time,
                            note);
          }
        }

        // Always free the heap-allocated string
        delete data_str;
      }
    } catch (...) {
      OutputDebugStringA(
          "[NATIVE] Error processing break confirmation message");
    }
    return 0;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::SetupPlatformChannel() {
  const static std::string channel_name = "com.attendance.tracker/system";

  flutter::MethodChannel<> channel(
      flutter_controller_->engine()->messenger(), channel_name,
      &flutter::StandardMethodCodec::GetInstance());

  platform_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(), channel_name,
      &flutter::StandardMethodCodec::GetInstance());

  auto handler = [this](const flutter::MethodCall<> &call,
                        std::unique_ptr<flutter::MethodResult<>> result) {
    HandleMethodCall(call, std::move(result));
  };

  platform_channel_->SetMethodCallHandler(handler);
}

void FlutterWindow::HandleMethodCall(
    const flutter::MethodCall<> &method_call,
    std::unique_ptr<flutter::MethodResult<>> result) {

  const std::string &method = method_call.method_name();

  if (method == "updateMenuBar") {
    // Same as updateTray for Windows
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      UpdateTrayFromFlutter(*args);
      result->Success();
    } else {
      result->Error("INVALID_ARGS", "Arguments must be a map");
    }
  } else if (method == "updateMenuItems") {
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      UpdateMenuItemsFromFlutter(*args);
      result->Success();
    } else {
      result->Error("INVALID_ARGS", "Arguments must be a map");
    }
  } else if (method == "getAutoStartStatus") {
    bool status = StartupManager::IsAutoStartEnabled();
    result->Success(flutter::EncodableValue(status));
  } else if (method == "setAutoStart") {
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        const auto *enabled = std::get_if<bool>(&it->second);
        if (enabled) {
          bool success = *enabled ? StartupManager::EnableAutoStart()
                                  : StartupManager::DisableAutoStart();
          result->Success(flutter::EncodableValue(success));
        } else {
          result->Error("INVALID_ARGS", "enabled must be a boolean");
        }
      } else {
        result->Error("INVALID_ARGS", "Missing enabled argument");
      }
    } else {
      result->Error("INVALID_ARGS", "Arguments must be a map");
    }
  } else if (method == "setSleepThreshold") {
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      auto it = args->find(flutter::EncodableValue("seconds"));
      if (it != args->end()) {
        const auto *seconds = std::get_if<int>(&it->second);
        if (seconds && power_monitor_) {
          power_monitor_->SetSleepThreshold(*seconds);
          result->Success();
        } else {
          result->Error("INVALID_ARGS", "seconds must be an integer");
        }
      } else {
        result->Error("INVALID_ARGS", "Missing seconds argument");
      }
    } else {
      result->Error("INVALID_ARGS", "Arguments must be a map");
    }
  } else if (method == "openSystemPreferences") {
    // Open Windows Settings for Startup Apps
    ShellExecute(NULL, L"open", L"ms-settings:startupapps", NULL, NULL,
                 SW_SHOWNORMAL);
    result->Success();
  } else if (method == "startActivityTracking") {
    if (window_tracker_) {
      window_tracker_->StartTracking();
      is_tracking_enabled_ = true;
      result->Success();
    } else {
      result->Error("NOT_INITIALIZED", "Window tracker not initialized");
    }
  } else if (method == "stopActivityTracking") {
    if (window_tracker_) {
      window_tracker_->StopTracking();
      is_tracking_enabled_ = false;
      result->Success();
    } else {
      result->Error("NOT_INITIALIZED", "Window tracker not initialized");
    }
  } else if (method == "getCurrentActivity") {
    if (window_tracker_) {
      auto activity = window_tracker_->GetCurrentActivity();
      flutter::EncodableMap activity_map;
      activity_map[flutter::EncodableValue("appName")] =
          flutter::EncodableValue(activity.app_name);
      activity_map[flutter::EncodableValue("windowTitle")] =
          flutter::EncodableValue(activity.window_title);
      activity_map[flutter::EncodableValue("bundleId")] =
          flutter::EncodableValue(activity.process_path);
      result->Success(flutter::EncodableValue(activity_map));
    } else {
      result->Error("NOT_INITIALIZED", "Window tracker not initialized");
    }
  } else if (method == "setAuthenticationStatus") {
    const auto *args =
        std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (args) {
      auto it = args->find(flutter::EncodableValue("isAuthenticated"));
      if (it != args->end()) {
        const auto *is_authenticated = std::get_if<bool>(&it->second);
        if (is_authenticated) {
          is_user_authenticated_ = *is_authenticated;
          std::wstring debug_msg =
              L"[AUTH] Authentication status updated: " +
              std::wstring(*is_authenticated ? L"true" : L"false") + L"\n";
          OutputDebugString(debug_msg.c_str());
          result->Success();
        } else {
          result->Error("INVALID_ARGS", "isAuthenticated must be a boolean");
        }
      } else {
        result->Error("INVALID_ARGS", "Missing isAuthenticated argument");
      }
    } else {
      result->Error("INVALID_ARGS", "Arguments must be a map");
    }
  } else if (method == "triggerBootEvent") {
    // Manually trigger boot event (called after successful login)
    OutputDebugString(L"[BOOT] Manually triggering boot event after login\n");
    NotifySystemBoot();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void FlutterWindow::SendSystemEvent(const std::string &event_type) {
  if (!platform_channel_)
    return;

  std::wstring debug_msg = L"[NATIVE] SendSystemEvent: " +
                           std::wstring(event_type.begin(), event_type.end()) +
                           L"\n";
  OutputDebugString(debug_msg.c_str());

  flutter::EncodableMap args;
  args[flutter::EncodableValue("event")] = flutter::EncodableValue(event_type);

  platform_channel_->InvokeMethod(
      "onSystemEvent", std::make_unique<flutter::EncodableValue>(args));
}

void FlutterWindow::SendActivityChange(const std::string &app_name,
                                       const std::string &window_title,
                                       const std::string &process_path) {
  if (!platform_channel_ || !is_tracking_enabled_)
    return;

  // Get current time in ISO8601 format
  SYSTEMTIME st;
  GetSystemTime(&st);
  char timestamp[32];
  snprintf(timestamp, sizeof(timestamp), "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
           st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
           st.wMilliseconds);

  flutter::EncodableMap args;
  args[flutter::EncodableValue("event")] =
      flutter::EncodableValue("activityChange");
  args[flutter::EncodableValue("appName")] = flutter::EncodableValue(app_name);
  args[flutter::EncodableValue("windowTitle")] =
      flutter::EncodableValue(window_title);
  args[flutter::EncodableValue("bundleId")] =
      flutter::EncodableValue(process_path);
  args[flutter::EncodableValue("timestamp")] =
      flutter::EncodableValue(std::string(timestamp));

  platform_channel_->InvokeMethod(
      "onActivityChange", std::make_unique<flutter::EncodableValue>(args));
}

void FlutterWindow::SendBreakConfirmation(bool was_on_break,
                                          const std::string &sleep_start,
                                          const std::string &wake_time,
                                          const std::string &note) {
  if (!platform_channel_)
    return;

  flutter::EncodableMap args;
  args[flutter::EncodableValue("wasOnBreak")] =
      flutter::EncodableValue(was_on_break);
  args[flutter::EncodableValue("sleepStart")] =
      flutter::EncodableValue(sleep_start);
  args[flutter::EncodableValue("wakeTime")] =
      flutter::EncodableValue(wake_time);
  if (!note.empty()) {
    args[flutter::EncodableValue("note")] = flutter::EncodableValue(note);
  }

  platform_channel_->InvokeMethod(
      "onBreakConfirmation", std::make_unique<flutter::EncodableValue>(args));
}

void FlutterWindow::HandleTrayMenuClick(int menu_id) {
  if (!platform_channel_)
    return;

  std::string action;
  switch (menu_id) {
  case ID_TRAY_CHECK_IN:
    action = "checkIn";
    break;
  case ID_TRAY_CHECK_OUT:
    action = "checkOut";
    break;
  case ID_TRAY_BREAK_IN:
    action = "breakIn";
    break;
  case ID_TRAY_BREAK_OUT:
    action = "breakOut";
    break;
  case ID_TRAY_SHOW_WINDOW:
    // Show the window when clicked from tray
    ShowWindow(GetHandle(), SW_SHOW);
    ShowWindow(GetHandle(), SW_RESTORE);
    SetForegroundWindow(GetHandle());
    return;
  case ID_TRAY_QUIT:
    // Send shutdown event to Flutter BEFORE destroying window
    // This gives Flutter time to save state (check-in/check-out/break times)
    OutputDebugString(
        L"[NATIVE] Quit requested, sending shutdown event to Flutter\n");
    SendSystemEvent("shutdown");

    // Set a timer to destroy window after 3 seconds (same as macOS)
    // This allows Flutter to:
    // 1. Receive and handle shutdown event
    // 2. Call saveSessionOnPause() to update last_seen_time
    // 3. Persist all attendance and break state to database
    SetTimer(GetHandle(), QUIT_TIMER_ID, 3000, NULL);
    return;
  default:
    return;
  }

  flutter::EncodableMap args;
  args[flutter::EncodableValue("action")] = flutter::EncodableValue(action);

  platform_channel_->InvokeMethod(
      "onUserAction", std::make_unique<flutter::EncodableValue>(args));
}

void FlutterWindow::UpdateTrayFromFlutter(const flutter::EncodableMap &args) {
  if (!system_tray_)
    return;

  auto it = args.find(flutter::EncodableValue("status"));
  if (it != args.end()) {
    const auto *status = std::get_if<std::string>(&it->second);
    if (status) {
      std::wstring wstatus(status->begin(), status->end());
      system_tray_->UpdateTooltip(wstatus);
    }
  }
}

void FlutterWindow::UpdateMenuItemsFromFlutter(
    const flutter::EncodableMap &args) {
  if (!system_tray_)
    return;
  // Support two payload formats from Flutter:
  // 1) Map with boolean keys: { "checkIn": true, "checkOut": false, ... }
  // 2) Map with a list under "enabledItems": ["Check In", "Break Out"]

  bool check_in = false;
  bool check_out = false;
  bool break_in = false;
  bool break_out = false;

  // Case A: explicit boolean map keys
  auto it_check_in = args.find(flutter::EncodableValue("checkIn"));
  if (it_check_in != args.end()) {
    const auto *value = std::get_if<bool>(&it_check_in->second);
    check_in = value ? *value : false;
  }

  auto it_check_out = args.find(flutter::EncodableValue("checkOut"));
  if (it_check_out != args.end()) {
    const auto *value = std::get_if<bool>(&it_check_out->second);
    check_out = value ? *value : false;
  }

  auto it_break_in = args.find(flutter::EncodableValue("breakIn"));
  if (it_break_in != args.end()) {
    const auto *value = std::get_if<bool>(&it_break_in->second);
    break_in = value ? *value : false;
  }

  auto it_break_out = args.find(flutter::EncodableValue("breakOut"));
  if (it_break_out != args.end()) {
    const auto *value = std::get_if<bool>(&it_break_out->second);
    break_out = value ? *value : false;
  }

  // Case B: list of enabled item titles (preferred from Dart side)
  auto it_enabled = args.find(flutter::EncodableValue("enabledItems"));
  if (it_enabled != args.end()) {
    const auto *list = std::get_if<flutter::EncodableList>(&it_enabled->second);
    if (list) {
      for (const auto &item : *list) {
        const auto *s = std::get_if<std::string>(&item);
        if (!s)
          continue;
        if (*s == "Check In")
          check_in = true;
        if (*s == "Check Out")
          check_out = true;
        if (*s == "Break In")
          break_in = true;
        if (*s == "Break Out")
          break_out = true;
      }
    }
  }

  system_tray_->UpdateMenuItems(check_in, check_out, break_in, break_out);
}

void FlutterWindow::StartMidnightMonitor() {
  // Start a timer that fires every minute to check for midnight
  SetTimer(GetHandle(), MIDNIGHT_TIMER_ID, 60000, NULL); // 60000ms = 1 minute
}

void FlutterWindow::CheckForMidnight() {
  SYSTEMTIME st;
  GetLocalTime(&st);

  // Check if it's midnight (00:00)
  if (st.wHour == 0 && st.wMinute == 0) {
    // Send midnight event to Flutter
    SendSystemEvent("midnight");
  }
}

void FlutterWindow::NotifySystemBoot() {
  // Only show boot dialog if user is authenticated
  if (!is_user_authenticated_) {
    OutputDebugString(L"[BOOT DIALOG] User not authenticated - skipping auto "
                      L"check-in dialog\n");
    return;
  }

  OutputDebugString(
      L"[BOOT DIALOG] === Starting Boot Confirmation Process ===\n");

  // FIX: Run the dialog on a background thread so the main Win32/Flutter
  // message pump is never blocked. Previously MessageBox was called directly
  // on the main thread, which froze the Flutter UI while the dialog was shown
  // and allowed partial user interaction with the app behind the dialog.
  std::thread([this]() {
    // Activate the window and bring it to foreground
    HWND hwnd = GetHandle();
    SetForegroundWindow(hwnd);
    SetActiveWindow(hwnd);
    BringWindowToTop(hwnd);

    OutputDebugString(
        L"[BOOT DIALOG] Window activated and brought to foreground\n");

    // Play system sound to get user's attention
    MessageBeep(MB_ICONQUESTION);
    OutputDebugString(L"[BOOT DIALOG] Sound notification played\n");

    // Small delay to ensure window is fully activated
    Sleep(100);

    OutputDebugString(L"[BOOT DIALOG] Displaying confirmation dialog...\n");

    // Show confirmation dialog with enhanced visibility flags
    int msgboxID =
        MessageBox(hwnd, L"System start detected. Do you want to check in now?",
                   L"Auto Check-In",
                   MB_ICONQUESTION | MB_YESNO | MB_DEFBUTTON1 | MB_TOPMOST |
                       MB_SETFOREGROUND);

    if (msgboxID == IDYES) {
      OutputDebugString(L"[BOOT DIALOG] ✓ User confirmed boot check-in - "
                        L"sending boot event\n");
      SendSystemEvent("boot");

      // No retry timer needed - Dart is already ready when triggered after
      // login The dialog is now shown AFTER user logs in, so handlers are
      // registered
      OutputDebugString(L"[BOOT DIALOG] Boot event sent (no retry needed)\n");
    } else if (msgboxID == IDNO) {
      OutputDebugString(L"[BOOT DIALOG] ✗ User declined boot check-in - "
                        L"staying checked out\n");
    } else {
      // Handle error or unexpected response
      wchar_t debug_msg[100];
      swprintf_s(debug_msg, L"[BOOT DIALOG] ⚠ Unexpected dialog response: %d\n",
                 msgboxID);
      OutputDebugString(debug_msg);
    }

    OutputDebugString(
        L"[BOOT DIALOG] === Boot Confirmation Process Complete ===\n");
  }).detach();
}
