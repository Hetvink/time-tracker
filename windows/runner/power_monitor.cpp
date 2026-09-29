#include "power_monitor.h"
#include <atomic>
#include <chrono>
#include <cstdint>
#include <iomanip>
#include <memory>
#include <sstream>
#include <thread>

PowerMonitor::PowerMonitor(HWND hwnd)
    : window_(hwnd), power_notify_(nullptr), is_sleeping_(false),
      is_showing_dialog_(false) {}

PowerMonitor::~PowerMonitor() {
  if (power_notify_) {
    UnregisterPowerSettingNotification(power_notify_);
  }
}

bool PowerMonitor::RegisterNotifications() {
  // Register for display state changes (sleep/wake)
  GUID guid = GUID_CONSOLE_DISPLAY_STATE;
  power_notify_ = RegisterPowerSettingNotification(window_, &guid,
                                                   DEVICE_NOTIFY_WINDOW_HANDLE);

  return power_notify_ != nullptr;
}

void PowerMonitor::HandlePowerEvent(WPARAM event) {
  if (!callback_)
    return;

  switch (event) {
  case PBT_APMSUSPEND:
    // System is suspending (sleep)
    GetLocalTime(&sleep_start_time_);
    is_sleeping_ = true;
    callback_("sleep");
    break;

  case PBT_APMRESUMEAUTOMATIC:
  case PBT_APMRESUMESUSPEND:
    // System is resuming from sleep
    if (is_sleeping_) {
      SYSTEMTIME wake_time;
      GetLocalTime(&wake_time);

      int duration_seconds =
          CalculateDurationSeconds(sleep_start_time_, wake_time);

      OutputDebugStringA("[WAKE] System resumed from sleep\n");
      char debug_msg[256];
      sprintf_s(debug_msg, "[WAKE] Sleep duration: %d seconds (%d minutes)\n",
                duration_seconds, duration_seconds / 60);
      OutputDebugStringA(debug_msg);
      sprintf_s(debug_msg, "[WAKE] Threshold: %d seconds (%d minutes)\n",
                sleep_threshold_seconds_, sleep_threshold_seconds_ / 60);
      OutputDebugStringA(debug_msg);

      if (duration_seconds >= sleep_threshold_seconds_) {
        OutputDebugStringA(
            "[WAKE] Long sleep detected - scheduling dialog after 2 second "
            "delay\n");

        // CRITICAL FIX: Add delay to allow system to fully wake up
        // After long sleep (>20 min), Windows needs time to restore display
        // and user session before showing dialogs
        std::thread([this, sleep_start = sleep_start_time_, wake_time,
                     duration_seconds]() {
          // Wait 2 seconds for system to fully wake up
          Sleep(2000);

          OutputDebugStringA("[WAKE] Delay complete - showing break dialog\n");
          ShowBreakConfirmationDialog(sleep_start, wake_time, duration_seconds);
        }).detach();
      } else {
        OutputDebugStringA(
            "[WAKE] Sleep duration below threshold - no dialog needed\n");
      }

      is_sleeping_ = false;
    }
    callback_("wake");
    break;

  case PBT_APMPOWERSTATUSCHANGE:
    // Power status changed (AC/battery)
    // Not used for attendance tracking
    break;
  }
}

bool PowerMonitor::HandleShutdown(WPARAM event) {
  if (!callback_)
    return true;

  // Notify Flutter about shutdown
  callback_("shutdown");

  // Give Flutter time to save data (8 seconds) to ensure proper database
  // closure This is critical for auto check-out to save the correct check-out
  // time
  Sleep(8000);

  // Allow shutdown to proceed
  return true;
}

void PowerMonitor::SetCallback(PowerEventCallback callback) {
  callback_ = callback;
}

void PowerMonitor::SetBreakConfirmationCallback(
    BreakConfirmationCallback callback) {
  break_callback_ = callback;
}

void PowerMonitor::SetSleepThreshold(int seconds) {
  sleep_threshold_seconds_ = seconds;
}

void PowerMonitor::ShowBreakConfirmationDialog(SYSTEMTIME sleep_start,
                                               SYSTEMTIME wake_time,
                                               int duration_seconds) {
  if (is_showing_dialog_)
    return;

  is_showing_dialog_ = true;

  // Create dialog on separate thread to avoid blocking
  std::thread([this, sleep_start, wake_time, duration_seconds]() {
    try {
      int minutes = duration_seconds / 60;
      int hours = minutes / 60;
      int remaining_minutes = minutes % 60;

      std::wstring time_str;
      if (hours > 0) {
        time_str =
            std::to_wstring(hours) + L" hour" + (hours == 1 ? L"" : L"s");
        if (remaining_minutes > 0) {
          time_str += L" and " + std::to_wstring(remaining_minutes) +
                      L" minute" + (remaining_minutes == 1 ? L"" : L"s");
        }
      } else {
        time_str =
            std::to_wstring(minutes) + L" minute" + (minutes == 1 ? L"" : L"s");
      }

      // Create title with time duration for immediate visibility
      std::wstring title =
          std::wstring(L"Break Confirmation - Idle for ") + time_str;

      std::wstring message =
          std::wstring(L"Were you on a break during this time?\n\n") +
          L"Click 'Yes' if you were on break.\n" +
          L"Click 'No' if you were working (this time will count as work "
          L"time).";

      // FIX: Use shared_ptr<atomic<bool>> so the timeout thread and dialog
      // thread can safely share the flag without dangling references.
      // Previously, local bool variables were captured by reference in a
      // detached thread, causing a crash ~30 seconds after the user answered
      // the dialog.
      auto has_responded = std::make_shared<std::atomic<bool>>(false);

      // Play system sound to alert user
      MessageBeep(MB_ICONQUESTION);
      OutputDebugStringA("[BREAK DIALOG] Playing alert sound\n");

      // Auto-dismiss timer thread
      // Capture has_responded by value (shared_ptr copy) - safe even after
      // outer lambda returns
      std::thread timeout_thread([this, has_responded, sleep_start, wake_time,
                                  title]() {
        Sleep(30000); // 30 seconds
        if (!has_responded->load()) {
          has_responded->store(true);
          OutputDebugStringA(
              "[BREAK DIALOG] Timed out after 30 seconds - defaulting to 'on "
              "break'\n");
          // Force close any open message box
          // Try to find and close dialog window (title now includes time)
          HWND hwnd = FindWindow(NULL, title.c_str());
          if (hwnd) {
            PostMessage(hwnd, WM_CLOSE, 0, 0);
          }
          // Send default response (on break) - is_showing_dialog_ will be reset
          // by SendBreakConfirmation
          SendBreakConfirmation(true, sleep_start, wake_time);
        }
      });
      timeout_thread.detach();

      OutputDebugStringA("[BREAK DIALOG] Displaying dialog to user\n");

      // Show message box with Yes/No buttons (blocking call)
      // Use MB_SYSTEMMODAL to ensure it appears above all windows
      int result =
          MessageBox(NULL, // Use NULL to make it top-level and always visible
                     message.c_str(), title.c_str(),
                     MB_YESNO | MB_ICONQUESTION | MB_SYSTEMMODAL |
                         MB_SETFOREGROUND | MB_TOPMOST);

      // Mark as responded immediately after MessageBox returns
      // This prevents timeout thread from interfering
      bool already_responded = has_responded->exchange(true);
      if (already_responded) {
        // Timeout thread already handled this - do nothing
        OutputDebugStringA("[BREAK DIALOG] Timeout already handled response\n");
        return;
      }

      bool was_on_break = (result == IDYES);

      char debug_msg[128];
      sprintf_s(debug_msg, "[BREAK DIALOG] User clicked: %s\n",
                was_on_break ? "Yes (on break)" : "No (working)");
      OutputDebugStringA(debug_msg);

      // If user was working, show note dialog
      if (!was_on_break) {
        OutputDebugStringA(
            "[BREAK DIALOG] Showing work note dialog for user input\n");
        ShowWorkNoteDialog(sleep_start, wake_time);
      } else {
        OutputDebugStringA("[BREAK DIALOG] Recording as break time\n");
        SendBreakConfirmation(was_on_break, sleep_start, wake_time);
      }
    } catch (const std::exception &e) {
      OutputDebugStringA("[BREAK DIALOG] Exception in dialog thread");
      OutputDebugStringA(e.what());
      // FIX: Always reset is_showing_dialog_ so future wake events work
      is_showing_dialog_ = false;
    } catch (...) {
      OutputDebugStringA("[BREAK DIALOG] Unknown exception in dialog thread");
      // FIX: Always reset is_showing_dialog_ so future wake events work
      is_showing_dialog_ = false;
    }
  }).detach();
}

void PowerMonitor::ShowWorkNoteDialog(SYSTEMTIME sleep_start,
                                      SYSTEMTIME wake_time) {
  // Small delay to let first dialog close
  Sleep(300);

  // Create input dialog for work note
  std::thread([this, sleep_start, wake_time]() {
    try {
      bool got_valid_note = false;
      std::string note;

      while (!got_valid_note) {
        // Use InputBox-style dialog (simpler than DialogBoxParam)
        // We'll create a dialog class and window on-the-fly

        // Register dialog window class
        WNDCLASSEXW wc = {0};
        wc.cbSize = sizeof(WNDCLASSEXW);
        wc.lpfnWndProc = WorkNoteDialogProc;
        wc.hInstance = GetModuleHandle(NULL);
        wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
        wc.lpszClassName = L"WorkNoteDialogClass";
        wc.hCursor = LoadCursor(NULL, IDC_ARROW);

        // Unregister first if already exists
        UnregisterClassW(L"WorkNoteDialogClass", GetModuleHandle(NULL));

        if (!RegisterClassExW(&wc)) {
          // Fallback to simple MessageBox if registration fails
          MessageBoxW(
              NULL, L"Please enter your work note in the console or settings.",
              L"Work Note Input", MB_OK | MB_ICONINFORMATION);
          note = "Work performed during system sleep";
          SendBreakConfirmation(false, sleep_start, wake_time, note);
          return;
        }

        // Create dialog data
        WorkNoteDialogData dialog_data;
        dialog_data.cancelled = false;

        // Create the dialog window
        HWND hwnd = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_DLGMODALFRAME, L"WorkNoteDialogClass",
            L"Work Note Required", WS_POPUP | WS_CAPTION | WS_SYSMENU,
            CW_USEDEFAULT, CW_USEDEFAULT, 400, 200, NULL, NULL,
            GetModuleHandle(NULL), &dialog_data);

        if (!hwnd) {
          // Fallback
          note = "Work performed during system sleep";
          SendBreakConfirmation(false, sleep_start, wake_time, note);
          UnregisterClassW(L"WorkNoteDialogClass", GetModuleHandle(NULL));
          return;
        }

        ShowWindow(hwnd, SW_SHOW);
        UpdateWindow(hwnd);
        SetForegroundWindow(hwnd);

        // Message loop
        MSG msg;
        while (GetMessage(&msg, NULL, 0, 0)) {
          if (msg.message == WM_QUIT || !IsWindow(hwnd)) {
            break;
          }
          TranslateMessage(&msg);
          DispatchMessage(&msg);
        }

        // Unregister class
        UnregisterClassW(L"WorkNoteDialogClass", GetModuleHandle(NULL));

        if (dialog_data.cancelled) {
          // User cancelled - show first dialog again
          Sleep(300);
          int duration_seconds =
              CalculateDurationSeconds(sleep_start, wake_time);
          ShowBreakConfirmationDialog(sleep_start, wake_time, duration_seconds);
          return;
        }

        // Convert wide string to UTF-8
        if (!dialog_data.note.empty()) {
          int size_needed = WideCharToMultiByte(
              CP_UTF8, 0, dialog_data.note.c_str(), -1, NULL, 0, NULL, NULL);
          std::string temp(size_needed - 1, 0);
          WideCharToMultiByte(CP_UTF8, 0, dialog_data.note.c_str(), -1,
                              &temp[0], size_needed, NULL, NULL);
          note = temp;

          // Trim whitespace
          size_t start = note.find_first_not_of(" \t\n\r");
          size_t end = note.find_last_not_of(" \t\n\r");
          if (start != std::string::npos && end != std::string::npos) {
            note = note.substr(start, end - start + 1);
          }

          if (!note.empty()) {
            got_valid_note = true;
          } else {
            // Show error - note is empty
            MessageBox(NULL,
                       L"Please provide a note to record work time.\n\n"
                       L"The note cannot be empty.",
                       L"Note Required",
                       MB_OK | MB_ICONWARNING | MB_SYSTEMMODAL);
          }
        } else {
          // Show error - note is empty
          MessageBox(NULL,
                     L"Please provide a note to record work time.\n\n"
                     L"The note cannot be empty.",
                     L"Note Required", MB_OK | MB_ICONWARNING | MB_SYSTEMMODAL);
        }
      }

      // Send confirmation with note
      SendBreakConfirmation(false, sleep_start, wake_time, note);
    } catch (const std::exception &e) {
      OutputDebugStringA("[WORK NOTE DIALOG] Exception in work note dialog");
      OutputDebugStringA(e.what());
      // Send fallback response to prevent crash
      SendBreakConfirmation(false, sleep_start, wake_time,
                            "Work performed during system sleep");
    } catch (...) {
      OutputDebugStringA(
          "[WORK NOTE DIALOG] Unknown exception in work note dialog");
      // Send fallback response to prevent crash
      SendBreakConfirmation(false, sleep_start, wake_time,
                            "Work performed during system sleep");
    }
  }).detach();
}

void PowerMonitor::SendBreakConfirmation(bool was_on_break,
                                         SYSTEMTIME sleep_start,
                                         SYSTEMTIME wake_time,
                                         const std::string &note) {
  // FIX: Always reset is_showing_dialog_ so future wake events show the dialog
  // again. Previously this was only reset in catch blocks, so after the first
  // successful dialog the flag stayed true and all future wake events would
  // skip the dialog.
  is_showing_dialog_ = false;

  if (!break_callback_) {
    return;
  }

  std::string sleep_start_str = SystemTimeToISO8601(sleep_start);
  std::string wake_time_str = SystemTimeToISO8601(wake_time);

  // FIX: Pack all data into a single string in lparam.
  // Previously was_on_break was passed as WPARAM (a new string*) which the
  // handler never read, causing a memory leak and was_on_break being lost.
  // Format: was_on_break|sleep_start|wake_time|note
  std::string packed = std::string(was_on_break ? "true" : "false") + "|" +
                       sleep_start_str + "|" + wake_time_str + "|" + note;

  // Post to main thread instead of calling directly
  // This prevents "non-platform thread" warnings and potential crashes
  PostMessage(window_, WM_USER + 100, 0,
              reinterpret_cast<LPARAM>(new std::string(packed)));
}

std::string PowerMonitor::SystemTimeToISO8601(const SYSTEMTIME &st) {
  std::ostringstream oss;
  oss << std::setfill('0') << std::setw(4) << st.wYear << "-" << std::setw(2)
      << st.wMonth << "-" << std::setw(2) << st.wDay << "T" << std::setw(2)
      << st.wHour << ":" << std::setw(2) << st.wMinute << ":" << std::setw(2)
      << st.wSecond << "." << std::setw(3) << st.wMilliseconds;
  return oss.str();
}

// Dialog procedure for work note input
LRESULT CALLBACK PowerMonitor::WorkNoteDialogProc(HWND hwnd, UINT msg,
                                                  WPARAM wParam,
                                                  LPARAM lParam) {
  static WorkNoteDialogData *dialog_data = nullptr;
  const int EDIT_CONTROL_ID = 101;
  const int OK_BUTTON_ID = 1;
  const int CANCEL_BUTTON_ID = 2;

  switch (msg) {
  case WM_CREATE: {
    // Get dialog data from CREATESTRUCT
    CREATESTRUCT *cs = reinterpret_cast<CREATESTRUCT *>(lParam);
    dialog_data = reinterpret_cast<WorkNoteDialogData *>(cs->lpCreateParams);

    // Center the dialog on screen
    RECT rect = {0, 0, 400, 200};
    int x = (GetSystemMetrics(SM_CXSCREEN) - 400) / 2;
    int y = (GetSystemMetrics(SM_CYSCREEN) - 200) / 2;
    SetWindowPos(hwnd, HWND_TOPMOST, x, y, 400, 200, SWP_SHOWWINDOW);

    // Create static text label
    CreateWindowW(L"STATIC", L"What were you working on?",
                  WS_VISIBLE | WS_CHILD | SS_LEFT, 10, 10, 360, 20, hwnd, NULL,
                  GetModuleHandle(NULL), NULL);

    // Create multiline edit control
    CreateWindowExW(
        WS_EX_CLIENTEDGE, L"EDIT", L"",
        WS_VISIBLE | WS_CHILD | WS_BORDER | ES_LEFT | ES_MULTILINE |
            ES_AUTOVSCROLL | WS_VSCROLL | WS_TABSTOP,
        10, 35, 360, 80, hwnd,
        reinterpret_cast<HMENU>(static_cast<uintptr_t>(EDIT_CONTROL_ID)),
        GetModuleHandle(NULL), NULL);

    // Create placeholder static text
    CreateWindowW(L"STATIC",
                  L"E.g., Working on client project, debugging issue...",
                  WS_VISIBLE | WS_CHILD | SS_LEFT, 15, 40, 350, 40, hwnd,
                  reinterpret_cast<HMENU>(static_cast<uintptr_t>(102)),
                  GetModuleHandle(NULL), NULL);

    // Create Submit button
    CreateWindowW(L"BUTTON", L"Submit",
                  WS_VISIBLE | WS_CHILD | BS_DEFPUSHBUTTON | WS_TABSTOP, 190,
                  125, 80, 25, hwnd,
                  reinterpret_cast<HMENU>(static_cast<uintptr_t>(OK_BUTTON_ID)),
                  GetModuleHandle(NULL), NULL);

    // Create Cancel button
    CreateWindowW(
        L"BUTTON", L"Cancel",
        WS_VISIBLE | WS_CHILD | BS_PUSHBUTTON | WS_TABSTOP, 280, 125, 90, 25,
        hwnd, reinterpret_cast<HMENU>(static_cast<uintptr_t>(CANCEL_BUTTON_ID)),
        GetModuleHandle(NULL), NULL);

    return 0;
  }

  case WM_COMMAND: {
    int ctrl_id = LOWORD(wParam);

    if (ctrl_id == OK_BUTTON_ID) {
      // Get text from edit control
      HWND edit = GetDlgItem(hwnd, EDIT_CONTROL_ID);
      int length = GetWindowTextLengthW(edit);

      if (length > 0) {
        std::wstring text(length + 1, L'\0');
        GetWindowTextW(edit, &text[0], length + 1);
        text.resize(length);

        if (dialog_data) {
          dialog_data->note = text;
          dialog_data->cancelled = false;
        }
        DestroyWindow(hwnd);
        PostQuitMessage(0);
      } else {
        // Show error if empty
        MessageBoxW(hwnd,
                    L"Please provide a note to record work time.\n\n"
                    L"The note cannot be empty.",
                    L"Note Required", MB_OK | MB_ICONWARNING);
      }
      return 0;
    } else if (ctrl_id == CANCEL_BUTTON_ID) {
      if (dialog_data) {
        dialog_data->cancelled = true;
      }
      DestroyWindow(hwnd);
      PostQuitMessage(0);
      return 0;
    } else if (ctrl_id == EDIT_CONTROL_ID && HIWORD(wParam) == EN_SETFOCUS) {
      // Hide placeholder when edit gets focus
      HWND placeholder = GetDlgItem(hwnd, 102);
      if (placeholder) {
        ShowWindow(placeholder, SW_HIDE);
      }
    } else if (ctrl_id == EDIT_CONTROL_ID && HIWORD(wParam) == EN_KILLFOCUS) {
      // Show placeholder if edit is empty when it loses focus
      HWND edit = GetDlgItem(hwnd, EDIT_CONTROL_ID);
      int length = GetWindowTextLengthW(edit);
      if (length == 0) {
        HWND placeholder = GetDlgItem(hwnd, 102);
        if (placeholder) {
          ShowWindow(placeholder, SW_SHOW);
        }
      }
    }
    break;
  }

  case WM_CLOSE:
    if (dialog_data) {
      dialog_data->cancelled = true;
    }
    DestroyWindow(hwnd);
    PostQuitMessage(0);
    return 0;

  case WM_DESTROY:
    PostQuitMessage(0);
    return 0;
  }

  return DefWindowProcW(hwnd, msg, wParam, lParam);
}

int PowerMonitor::CalculateDurationSeconds(const SYSTEMTIME &start,
                                           const SYSTEMTIME &end) {
  FILETIME ft_start, ft_end;
  SystemTimeToFileTime(&start, &ft_start);
  SystemTimeToFileTime(&end, &ft_end);

  ULARGE_INTEGER uli_start, uli_end;
  uli_start.LowPart = ft_start.dwLowDateTime;
  uli_start.HighPart = ft_start.dwHighDateTime;
  uli_end.LowPart = ft_end.dwLowDateTime;
  uli_end.HighPart = ft_end.dwHighDateTime;

  // Convert from 100-nanosecond intervals to seconds
  return static_cast<int>((uli_end.QuadPart - uli_start.QuadPart) / 10000000);
}
